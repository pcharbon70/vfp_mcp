defmodule VfpMcp.Codec.Tree do
  @moduledoc """
  Deterministic containment, validation, and path construction for VFP objects.

  Parent resolution uses case-insensitive OBJNAME indexes rather than record
  adjacency. Invalid relationships remain visible on objects but never enter
  the unambiguous path index.
  """

  # specled covers:
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.full_path_identity
  # - vfp_mcp.read.validation_findings

  alias VfpMcp.{Finding, Limits, SemanticValue, SourceObject}
  alias VfpMcp.Source.Path

  @container_classes ~w(formset form pageframe page grid column container optiongroup commandgroup toolbar)

  @type tree :: %{
          roots: [non_neg_integer()],
          children: %{optional(non_neg_integer()) => [non_neg_integer()]}
        }

  @spec build([SourceObject.t()], Limits.t()) ::
          {:ok, [SourceObject.t()], tree(), %{optional(String.t()) => SourceObject.t()},
           [Finding.t()]}
  def build(objects, %Limits{} = limits) do
    by_record = Map.new(objects, &{&1.record_index, &1})
    name_index = Enum.group_by(objects, &(identity(&1, :objname) |> canonical()))
    name_findings = missing_name_findings(objects)

    {parent_states, relationship_findings} = resolve_parents(objects, name_index)
    {cycle_records, cycle_findings} = cycles(parent_states, by_record)
    {depth_records, depth_findings} = excessive_depth(parent_states, by_record, limits)
    invalid_records = MapSet.union(cycle_records, depth_records)

    objects =
      Enum.map(objects, fn object ->
        parent_record_index =
          case Map.get(parent_states, object.record_index) do
            {:resolved, parent} -> parent
            _other -> nil
          end

        path = path_for(object, parent_states, by_record, invalid_records, limits)
        %{object | parent_record_index: parent_record_index, path: path}
      end)

    {path_index, path_findings, ambiguous_records} = path_index(objects)

    objects =
      Enum.map(objects, fn object ->
        if MapSet.member?(ambiguous_records, object.record_index) do
          %{object | edit_eligibility: {:blocked, [:hierarchy_path_ambiguous]}}
        else
          object
        end
      end)

    indexed_records = path_index |> Map.values() |> MapSet.new(& &1.record_index)

    roots =
      objects
      |> Enum.filter(fn object ->
        MapSet.member?(indexed_records, object.record_index) and
          Map.get(parent_states, object.record_index) == :root
      end)
      |> Enum.map(& &1.record_index)
      |> Enum.sort()

    children =
      objects
      |> Enum.filter(&MapSet.member?(indexed_records, &1.record_index))
      |> Enum.reduce(%{}, fn object, acc ->
        case object.parent_record_index do
          nil -> acc
          parent -> Map.update(acc, parent, [object.record_index], &[object.record_index | &1])
        end
      end)
      |> Map.new(fn {parent, child_records} -> {parent, Enum.sort(child_records)} end)

    findings =
      name_findings ++ relationship_findings ++ cycle_findings ++ depth_findings ++ path_findings

    {:ok, objects, %{roots: roots, children: children}, path_index, findings}
  end

  @spec lookup(map(), String.t()) :: {:ok, SourceObject.t()} | {:error, atom()}
  def lookup(path_index, path) when is_map(path_index) do
    with {:ok, canonical_path} <- Path.canonicalize(path),
         {:ok, object} <- Map.fetch(path_index, canonical_path) do
      {:ok, object}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      :error -> {:error, :object_path_not_found}
    end
  end

  defp resolve_parents(objects, name_index) do
    Enum.reduce(objects, {%{}, []}, fn object, {states, findings} ->
      parent_name = identity(object, :parent) |> String.trim()

      if parent_name == "" do
        {Map.put(states, object.record_index, :root), findings}
      else
        case Map.get(name_index, canonical(parent_name), []) do
          [] ->
            finding = relationship_finding(:hierarchy_parent_missing, object, parent_name, %{})
            {Map.put(states, object.record_index, {:invalid, :missing}), [finding | findings]}

          [parent] when parent.record_index == object.record_index ->
            finding = relationship_finding(:hierarchy_self_parent, object, parent_name, %{})
            {Map.put(states, object.record_index, {:invalid, :self}), [finding | findings]}

          [parent] ->
            if container?(parent) do
              {Map.put(states, object.record_index, {:resolved, parent.record_index}), findings}
            else
              finding =
                relationship_finding(:hierarchy_incompatible_parent, object, parent_name, %{
                  parent_record: parent.record_index,
                  parent_baseclass: canonical(identity(parent, :baseclass))
                })

              {Map.put(states, object.record_index, {:invalid, :incompatible}),
               [finding | findings]}
            end

          candidates ->
            candidate_records = candidates |> Enum.map(& &1.record_index) |> Enum.sort()

            finding =
              relationship_finding(:hierarchy_parent_ambiguous, object, parent_name, %{
                candidates: candidate_records
              })

            {Map.put(states, object.record_index, {:invalid, :ambiguous}), [finding | findings]}
        end
      end
    end)
    |> then(fn {states, findings} -> {states, Enum.reverse(findings)} end)
  end

  defp missing_name_findings(objects) do
    for object <- objects, String.trim(identity(object, :objname)) == "" do
      Finding.new(
        :hierarchy_object_name_missing,
        :error,
        :mutation_blocked,
        "object has no usable OBJNAME for hierarchy identity",
        location: %{record: object.record_index, field: "OBJNAME"},
        evidence: %{record: object.record_index}
      )
    end
  end

  defp cycles(parent_states, by_record) do
    cycles =
      parent_states
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce(MapSet.new(), fn record, cycles ->
        case walk(record, parent_states, [], MapSet.new(), map_size(by_record) + 1) do
          {:cycle, records} -> MapSet.put(cycles, normalize_cycle(records))
          _other -> cycles
        end
      end)

    records = cycles |> Enum.flat_map(&Tuple.to_list/1) |> MapSet.new()

    findings =
      cycles
      |> Enum.sort()
      |> Enum.map(fn cycle ->
        cycle_records = Tuple.to_list(cycle)
        record = hd(cycle_records)
        object = Map.fetch!(by_record, record)

        Finding.new(
          :hierarchy_cycle,
          :error,
          :mutation_blocked,
          "object containment contains a cycle",
          location: %{record: record, field: "PARENT"},
          evidence: %{records: cycle_records, object: canonical(identity(object, :objname))}
        )
      end)

    {records, findings}
  end

  defp excessive_depth(parent_states, by_record, limits) do
    records =
      parent_states
      |> Map.keys()
      |> Enum.filter(fn record ->
        match?(
          {:depth, _records},
          walk(record, parent_states, [], MapSet.new(), limits.hierarchy_depth)
        )
      end)
      |> MapSet.new()

    findings =
      records
      |> Enum.sort()
      |> Enum.map(fn record ->
        object = Map.fetch!(by_record, record)

        Finding.new(
          :limit_hierarchy_depth_exceeded,
          :error,
          :mutation_blocked,
          "object containment exceeds the configured hierarchy depth",
          location: %{record: record, field: "PARENT"},
          evidence: %{
            maximum: limits.hierarchy_depth,
            object: canonical(identity(object, :objname))
          }
        )
      end)

    {records, findings}
  end

  defp walk(_record, _states, trail, _seen, remaining) when remaining < 0,
    do: {:depth, trail}

  defp walk(record, states, trail, seen, remaining) do
    if MapSet.member?(seen, record) do
      cycle = trail |> Enum.drop_while(&(&1 != record)) |> Enum.uniq()
      {:cycle, cycle}
    else
      case Map.get(states, record) do
        {:resolved, parent} ->
          walk(parent, states, trail ++ [record], MapSet.put(seen, record), remaining - 1)

        _root_or_invalid ->
          :ok
      end
    end
  end

  defp normalize_cycle(records), do: records |> Enum.sort() |> List.to_tuple()

  defp path_for(object, parent_states, by_record, invalid_records, limits) do
    case collect_segments(
           object.record_index,
           parent_states,
           by_record,
           invalid_records,
           limits.hierarchy_depth,
           []
         ) do
      {:ok, segments} -> Path.build(segments)
      :invalid -> nil
    end
  end

  defp collect_segments(_record, _states, _objects, _invalid, remaining, _segments)
       when remaining < 0,
       do: :invalid

  defp collect_segments(record, states, objects, invalid, remaining, segments) do
    object = Map.fetch!(objects, record)
    name = identity(object, :objname) |> String.trim()

    cond do
      name == "" ->
        :invalid

      MapSet.member?(invalid, record) ->
        :invalid

      true ->
        case Map.get(states, record) do
          :root ->
            {:ok, [name | segments]}

          {:resolved, parent} ->
            collect_segments(parent, states, objects, invalid, remaining - 1, [name | segments])

          {:invalid, _reason} ->
            :invalid
        end
    end
  end

  defp path_index(objects) do
    groups =
      objects
      |> Enum.reject(&is_nil(&1.path))
      |> Enum.group_by(fn object ->
        {:ok, canonical_path} = Path.canonicalize(object.path)
        canonical_path
      end)

    Enum.reduce(groups, {%{}, [], MapSet.new()}, fn {canonical_path, candidates},
                                                    {index, findings, ambiguous} ->
      case candidates do
        [object] ->
          {Map.put(index, canonical_path, object), findings, ambiguous}

        candidates ->
          records = candidates |> Enum.map(& &1.record_index) |> Enum.sort()
          paths = candidates |> Enum.map(& &1.path) |> Enum.uniq() |> Enum.sort()

          code =
            if length(paths) == 1,
              do: :hierarchy_duplicate_sibling,
              else: :hierarchy_path_canonicalization_collision

          finding =
            Finding.new(
              code,
              :error,
              :mutation_blocked,
              "multiple objects resolve to the same canonical path",
              location: %{object_path: canonical_path},
              evidence: %{records: records, paths: paths}
            )

          next_ambiguous = Enum.reduce(records, ambiguous, &MapSet.put(&2, &1))
          {index, [finding | findings], next_ambiguous}
      end
    end)
    |> then(fn {index, findings, ambiguous} -> {index, Enum.reverse(findings), ambiguous} end)
  end

  defp relationship_finding(code, object, parent_name, extra_evidence) do
    Finding.new(
      code,
      :error,
      :mutation_blocked,
      relationship_message(code),
      location: %{record: object.record_index, field: "PARENT"},
      evidence: Map.merge(%{parent: canonical(parent_name)}, extra_evidence)
    )
  end

  defp relationship_message(:hierarchy_parent_missing), do: "parent object cannot be resolved"
  defp relationship_message(:hierarchy_self_parent), do: "object cannot contain itself"

  defp relationship_message(:hierarchy_incompatible_parent),
    do: "resolved parent base class is not a supported container"

  defp relationship_message(:hierarchy_parent_ambiguous),
    do: "parent name resolves to more than one object"

  defp container?(object), do: canonical(identity(object, :baseclass)) in @container_classes

  defp identity(object, field) do
    case Map.get(object.identity_fields, field) do
      %SemanticValue{value: value} -> value
      nil -> ""
    end
  end

  defp canonical(value), do: value |> String.trim() |> String.downcase()
end
