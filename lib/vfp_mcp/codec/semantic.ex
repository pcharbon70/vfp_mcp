defmodule VfpMcp.Codec.Semantic do
  @moduledoc """
  Converts a bounded physical DBF/FPT model into provenance-bearing records.

  This stage recognizes only established VFP identity fields. Missing,
  duplicated, undecodable, and unsupported values remain physical data and
  produce findings instead of positional guesses.
  """

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.validation_findings
  # - vfp_mcp.read.source_fidelity
  # - vfp_mcp.protocol.sdk_boundary

  alias VfpMcp.Codec.{Dbf, Fpt}
  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.{Finding, SemanticRecord, SemanticValue, SourceObject}

  @identity_fields %{
    "CLASS" => :class,
    "BASECLASS" => :baseclass,
    "OBJNAME" => :objname,
    "PARENT" => :parent,
    "CLASSLOC" => :classloc,
    "PLATFORM" => :platform,
    "UNIQUEID" => :uniqueid
  }
  @required_identity_fields ["CLASS", "BASECLASS", "OBJNAME", "PARENT", "CLASSLOC"]
  @data_environment_classes ["dataenvironment", "cursor", "relation"]

  @type result ::
          {:ok, [SemanticRecord.t()], [SourceObject.t()], [SemanticRecord.t()], [Finding.t()]}

  @spec build(Dbf.t(), Fpt.t(), [TextValue.t()]) :: result()
  def build(%Dbf{} = dbf, %Fpt{} = fpt, text_views) when is_list(text_views) do
    schema = schema_index(dbf.fields)
    text_index = text_index(text_views)
    memo_index = Enum.group_by(fpt.memo_refs, & &1.record_index)
    schema_findings = schema_findings(schema)
    last_index = max(length(dbf.records) - 1, 0)

    {semantic_records, record_findings} =
      dbf.records
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {record, semantic_index}, findings ->
        {identity_fields, identity_findings} =
          identity_fields(record, schema, text_index, memo_index)

        category = classify(identity_fields, record.index, last_index)
        memo_refs = Map.get(memo_index, record.index, [])

        semantic_record = %SemanticRecord{
          semantic_index: semantic_index,
          record_index: record.index,
          category: category,
          physical_record: record,
          identity_fields: identity_fields,
          raw_fields: record.values,
          memo_refs: memo_refs,
          spans:
            [record.span, record.marker_span] ++
              Enum.map(record.values, & &1.span) ++
              Enum.flat_map(memo_refs, &memo_spans/1)
        }

        {semantic_record, findings ++ identity_findings}
      end)

    objects =
      for record <- semantic_records, record.category == :object do
        %SourceObject{
          semantic_index: record.semantic_index,
          record_index: record.record_index,
          category: record.category,
          active?: record.physical_record.deleted? == false,
          identity_fields: record.identity_fields,
          raw_fields: record.raw_fields,
          memo_refs: record.memo_refs,
          spans: record.spans
        }
      end

    data_environment =
      Enum.filter(
        semantic_records,
        &(&1.category in [:data_environment, :data_environment_entry])
      )

    {:ok, semantic_records, objects, data_environment, schema_findings ++ record_findings}
  end

  defp schema_index(fields) do
    Enum.group_by(fields, &canonical_field(&1.name))
  end

  defp text_index(text_views) do
    Enum.group_by(text_views, fn view -> {view.record_index, canonical_field(view.field)} end)
  end

  defp schema_findings(schema) do
    Enum.flat_map(@required_identity_fields, fn field ->
      case Map.get(schema, field, []) do
        [] ->
          [
            Finding.new(
              :semantic_identity_field_missing,
              :error,
              :mutation_blocked,
              "required semantic identity field is absent",
              location: %{member: :dbf, offset: 32},
              evidence: %{field: field}
            )
          ]

        [_field] ->
          []

        duplicates ->
          [
            Finding.new(
              :semantic_identity_field_ambiguous,
              :error,
              :mutation_blocked,
              "semantic identity field is duplicated",
              location: %{member: :dbf, offset: hd(duplicates).descriptor_span.offset},
              evidence: %{field: field, count: length(duplicates)}
            )
          ]
      end
    end)
  end

  defp identity_fields(record, schema, text_index, memo_index) do
    Enum.reduce(@identity_fields, {%{}, []}, fn {physical_name, semantic_name},
                                                {values, findings} ->
      case Map.get(schema, physical_name, []) do
        [field] ->
          case semantic_value(record, field, text_index, memo_index) do
            {:ok, value} ->
              {Map.put(values, semantic_name, value), findings}

            {:error, finding} ->
              {values, [finding | findings]}
          end

        _missing_or_ambiguous ->
          {values, findings}
      end
    end)
    |> then(fn {values, findings} -> {values, Enum.reverse(findings)} end)
  end

  defp semantic_value(record, field, text_index, memo_index) do
    physical_value = Enum.find(record.values, &(&1.field_index == field.index))
    key = {record.index, canonical_field(field.name)}

    case {field.type, Map.get(text_index, key, []),
          memo_for(memo_index, record.index, field.name)} do
      {:character, [%TextValue{text: text}], _memo} when is_binary(text) ->
        {:ok, value(field, physical_value, trim_fixed(text), nil)}

      {:memo, [%TextValue{text: text}], memo} when is_binary(text) ->
        {:ok, value(field, physical_value, text, memo)}

      {:memo, [], %{resolution: :empty} = memo} ->
        {:ok, value(field, physical_value, "", memo)}

      {_type, [], _memo} ->
        {:error,
         Finding.new(
           :semantic_identity_value_unavailable,
           :error,
           :mutation_blocked,
           "semantic identity value cannot be decoded safely",
           location: %{record: record.index, field: field.name},
           evidence: %{field_type: field.type}
         )}

      {_type, views, _memo} ->
        {:error,
         Finding.new(
           :semantic_identity_value_ambiguous,
           :error,
           :mutation_blocked,
           "semantic identity value has multiple decoded sources",
           location: %{record: record.index, field: field.name},
           evidence: %{sources: length(views)}
         )}
    end
  end

  defp value(field, physical_value, text, memo_ref) do
    source_span =
      if memo_ref && memo_ref.payload_span, do: memo_ref.payload_span, else: physical_value.span

    raw_bytes =
      if memo_ref && is_binary(memo_ref.payload_bytes),
        do: memo_ref.payload_bytes,
        else: physical_value.raw_bytes

    %SemanticValue{
      field: field.name,
      field_index: field.index,
      value: text,
      raw_bytes: raw_bytes,
      span: source_span,
      memo_ref: memo_ref
    }
  end

  defp memo_for(memo_index, record_index, field_name) do
    memo_index
    |> Map.get(record_index, [])
    |> Enum.find(&(canonical_field(&1.field) == canonical_field(field_name)))
  end

  defp classify(fields, index, last_index) do
    platform = semantic_text(fields, :platform) |> canonical_text()
    baseclass = semantic_text(fields, :baseclass) |> canonical_text()
    objname = semantic_text(fields, :objname)

    cond do
      platform == "comment" and index == 0 -> :bookend_open
      platform == "comment" and index == last_index -> :bookend_close
      platform == "comment" -> :comment
      baseclass == "dataenvironment" -> :data_environment
      baseclass in @data_environment_classes -> :data_environment_entry
      present?(objname) or present?(baseclass) -> :object
      true -> :unknown
    end
  end

  defp semantic_text(fields, key) do
    case Map.get(fields, key) do
      %SemanticValue{value: value} -> value
      nil -> ""
    end
  end

  defp present?(value), do: value != ""
  defp canonical_text(text), do: text |> String.trim() |> String.downcase()
  defp canonical_field(field), do: field |> String.trim() |> String.upcase()
  defp trim_fixed(text), do: String.trim_trailing(text, <<0>>) |> String.trim_trailing()

  defp memo_spans(memo_ref) do
    [memo_ref.pointer_span, memo_ref.block_span, memo_ref.payload_span, memo_ref.allocation_span]
    |> Enum.reject(&is_nil/1)
  end
end
