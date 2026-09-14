defmodule VfpMcp.Validate do
  @moduledoc """
  Stable rule metadata, ordering, and eligibility for semantic findings.

  Validation never repairs input. It sorts bounded evidence and derives
  explicit document- and object-level mutation eligibility from finding impact.
  """

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.validation_findings

  alias VfpMcp.{Finding, Limits, SourceObject}

  @rules %{
    semantic_identity_field_missing: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :schema
    },
    semantic_identity_field_ambiguous: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :schema
    },
    semantic_identity_value_unavailable: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :object
    },
    semantic_identity_value_ambiguous: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :object
    },
    semantic_vfp_version_undeclared: %{
      severity: :info,
      impact: :informational,
      scope: :pair
    },
    semantic_dbf_format_unsupported: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :pair
    },
    hierarchy_object_name_missing: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :object
    },
    hierarchy_parent_missing: %{severity: :error, impact: :mutation_blocked, scope: :object},
    hierarchy_parent_ambiguous: %{severity: :error, impact: :mutation_blocked, scope: :object},
    hierarchy_self_parent: %{severity: :error, impact: :mutation_blocked, scope: :object},
    hierarchy_cycle: %{severity: :error, impact: :mutation_blocked, scope: :objects},
    hierarchy_incompatible_parent: %{severity: :error, impact: :mutation_blocked, scope: :object},
    limit_hierarchy_depth_exceeded: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :object
    },
    hierarchy_duplicate_sibling: %{severity: :error, impact: :mutation_blocked, scope: :objects},
    hierarchy_path_canonicalization_collision: %{
      severity: :error,
      impact: :mutation_blocked,
      scope: :objects
    },
    property_duplicate_assignment: %{severity: :error, impact: :mutation_blocked, scope: :object},
    property_malformed_string: %{severity: :error, impact: :mutation_blocked, scope: :object},
    property_unsupported_literal: %{severity: :warning, impact: :preserved, scope: :line},
    property_continuation: %{severity: :warning, impact: :preserved, scope: :line},
    property_unsupported_line: %{severity: :warning, impact: :preserved, scope: :line},
    property_memo_ambiguous: %{severity: :error, impact: :mutation_blocked, scope: :object},
    method_duplicate_name: %{severity: :error, impact: :mutation_blocked, scope: :object},
    method_nested_procedure: %{severity: :error, impact: :mutation_blocked, scope: :object},
    method_unmatched_endproc: %{severity: :error, impact: :mutation_blocked, scope: :object},
    method_missing_endproc: %{severity: :error, impact: :mutation_blocked, scope: :object},
    method_memo_ambiguous: %{severity: :error, impact: :mutation_blocked, scope: :object}
  }

  @spec rule_matrix() :: map()
  def rule_matrix, do: @rules

  @spec finalize([Finding.t()], Limits.t()) :: {:ok, [Finding.t()]} | {:error, [Finding.t()]}
  def finalize(findings, %Limits{} = limits) do
    findings = Enum.sort_by(findings, &sort_key/1)

    if length(findings) <= limits.findings do
      {:ok, findings}
    else
      {:error,
       [
         Finding.fatal(:limit_findings_exceeded, "findings limit exceeded",
           evidence: %{actual: length(findings), maximum: limits.findings}
         )
       ]}
    end
  end

  @spec document_eligibility([Finding.t()]) :: :eligible | {:blocked, [atom()]}
  def document_eligibility(findings) do
    findings
    |> Enum.filter(&(&1.impact == :mutation_blocked))
    |> Enum.map(& &1.code)
    |> eligibility()
  end

  @spec apply_object_eligibility([SourceObject.t()], [Finding.t()]) :: [SourceObject.t()]
  def apply_object_eligibility(objects, findings) do
    Enum.map(objects, fn object ->
      local_codes =
        findings
        |> Enum.filter(&(&1.impact == :mutation_blocked and applies_to?(&1, object)))
        |> Enum.map(& &1.code)

      existing_codes =
        case object.edit_eligibility do
          {:blocked, codes} -> codes
          _other -> []
        end

      %{object | edit_eligibility: eligibility(existing_codes ++ local_codes)}
    end)
  end

  defp applies_to?(finding, object) do
    location = finding.location || %{}
    record = Map.get(location, :record) || Map.get(finding.evidence, :record)
    records = Map.get(finding.evidence, :records, [])
    object_path = Map.get(location, :object_path)

    cond do
      is_integer(record) -> record == object.record_index
      is_list(records) and records != [] -> object.record_index in records
      is_binary(object_path) -> canonical_path(object.path) == object_path
      global_finding?(finding) -> true
      true -> false
    end
  end

  defp global_finding?(finding) do
    case finding.location do
      %{member: :dbf, offset: offset} when offset <= 32 -> true
      nil -> true
      _local -> false
    end
  end

  defp canonical_path(nil), do: nil

  defp canonical_path(path) do
    case VfpMcp.Source.Path.canonicalize(path) do
      {:ok, canonical} -> canonical
      {:error, _reason} -> nil
    end
  end

  defp eligibility(codes) do
    codes = codes |> Enum.uniq() |> Enum.sort()
    if codes == [], do: :eligible, else: {:blocked, codes}
  end

  defp sort_key(finding) do
    semantic_identity =
      {
        Map.get(finding.evidence, :record, -1),
        Map.get(finding.evidence, :property, ""),
        Map.get(finding.evidence, :method, "")
      }

    {location_key(finding.location), Atom.to_string(finding.code), semantic_identity}
  end

  defp location_key(%{member: :dbf, offset: offset}), do: {0, offset}
  defp location_key(%{member: :fpt, offset: offset}), do: {1, offset}
  defp location_key(%{record: record, field: field}), do: {2, record, field}
  defp location_key(%{record: record}), do: {2, record, ""}
  defp location_key(%{object_path: path}), do: {3, path}
  defp location_key(nil), do: {4}
  defp location_key(other), do: {5, inspect(other)}
end
