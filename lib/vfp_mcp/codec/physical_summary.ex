defmodule VfpMcp.Codec.PhysicalSummary do
  @moduledoc """
  Deterministic, bounded summaries of a decoded physical source pair.

  Summaries expose offsets, lengths, scalar metadata, and SHA-256 values. They
  deliberately omit raw field names, field values, and memo payload content.
  """

  # specled covers:
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Codec.{Dbf, Fpt}
  alias VfpMcp.Document

  @schema_version 1

  @spec summarize(Document.t()) :: map()
  def summarize(%Document{physical: %{dbf: %Dbf{} = dbf, fpt: %Fpt{} = fpt}} = document) do
    %{
      "schema_version" => @schema_version,
      "pair" => %{
        "kind" => Atom.to_string(document.pair.kind),
        "pair_sha256" => document.pair.pair_sha256,
        "source_id_sha256" => hash(document.pair.source_id),
        "vfp_version" => document.version,
        "encoding" => atom_string(document.encoding)
      },
      "dbf" => dbf_summary(dbf),
      "fpt" => fpt_summary(fpt),
      "findings" => Enum.map(document.findings, &finding_summary/1)
    }
  end

  @spec encode(Document.t()) :: binary()
  def encode(%Document{} = document) do
    document
    |> summarize()
    |> canonicalize()
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  defp dbf_summary(dbf) do
    %{
      "member" => region(dbf.bytes, 0),
      "header" => %{
        "format" => dbf.header.format,
        "date_bytes_sha256" => hash(dbf.header.date_bytes),
        "record_count" => dbf.header.record_count,
        "header_length" => dbf.header.header_length,
        "record_length" => dbf.header.record_length,
        "code_page" => dbf.header.code_page,
        "region" => region(dbf.header_bytes, 0)
      },
      "descriptors_region" => region(dbf.descriptor_bytes, 32),
      "header_extension_region" =>
        region(
          dbf.header_extension_bytes,
          dbf.terminator_span.offset + dbf.terminator_span.length
        ),
      "records_region" => region(dbf.records_bytes, dbf.header.header_length),
      "trailing_region" =>
        region(
          dbf.trailing_bytes,
          dbf.header.header_length + byte_size(dbf.records_bytes)
        ),
      "fields" => Enum.map(dbf.fields, &field_summary/1),
      "records" => Enum.map(dbf.records, &record_summary/1)
    }
  end

  defp field_summary(field) do
    %{
      "index" => field.index,
      "name_sha256" => hash(field.name),
      "type" => Atom.to_string(field.type),
      "type_byte" => field.type_byte,
      "length" => field.length,
      "decimal_count" => field.decimal_count,
      "flags" => field.flags,
      "record_offset" => field.record_offset,
      "descriptor" => span_region(field.raw_bytes, field.descriptor_span)
    }
  end

  defp record_summary(record) do
    %{
      "index" => record.index,
      "marker" => record.marker,
      "deleted" => record.deleted?,
      "region" => span_region(record.raw_bytes, record.span),
      "values" =>
        Enum.map(record.values, fn value ->
          %{
            "field_index" => value.field_index,
            "field_name_sha256" => hash(value.field_name),
            "type" => Atom.to_string(value.type),
            "region" => span_region(value.raw_bytes, value.span)
          }
        end)
    }
  end

  defp fpt_summary(fpt) do
    %{
      "member" => region(fpt.bytes, 0),
      "header" => %{
        "next_free_block" => fpt.header.next_free_block,
        "stored_block_size" => fpt.header.stored_block_size,
        "effective_block_size" => fpt.header.effective_block_size,
        "first_data_block" => fpt.header.first_data_block,
        "data_offset" => fpt.header.data_offset,
        "next_free_offset" => fpt.header.next_free_offset,
        "region" => region(fpt.header_bytes, 0)
      },
      "pre_data_region" => region(fpt.pre_data_bytes, 512),
      "allocation_region" => region(fpt.allocation_bytes, fpt.header.data_offset),
      "trailing_region" => region(fpt.trailing_bytes, fpt.header.next_free_offset),
      "blocks" =>
        fpt.blocks
        |> Map.values()
        |> Enum.sort_by(& &1.pointer)
        |> Enum.map(&block_summary/1),
      "memo_references" => Enum.map(fpt.memo_refs, &memo_ref_summary/1)
    }
  end

  defp block_summary(block) do
    %{
      "pointer" => block.pointer,
      "offset" => block.offset,
      "block_type" => block.block_type,
      "payload_length" => block.payload_length,
      "valid" => block.valid?,
      "header" => span_region(block.raw_header_bytes, block.header_span),
      "payload" => span_region(block.payload_bytes, block.payload_span),
      "padding" => %{
        "length" => byte_size(block.padding_bytes),
        "sha256" => hash(block.padding_bytes)
      },
      "allocation" => span_region(block.allocation_bytes, block.allocation_span)
    }
  end

  defp memo_ref_summary(memo_ref) do
    %{
      "record_index" => memo_ref.record_index,
      "field_name_sha256" => hash(memo_ref.field),
      "pointer" => memo_ref.pointer,
      "pointer_bytes_sha256" => hash(memo_ref.pointer_bytes),
      "pointer_span" => span_summary(memo_ref.pointer_span),
      "resolution" => term_string(memo_ref.resolution),
      "block_id" => memo_ref.block_id
    }
  end

  defp finding_summary(finding) do
    %{
      "code" => Atom.to_string(finding.code),
      "severity" => Atom.to_string(finding.severity),
      "impact" => Atom.to_string(finding.impact),
      "location" => json_term(finding.location),
      "evidence" => json_term(finding.evidence)
    }
  end

  defp span_region(bytes, span) do
    span |> span_summary() |> Map.put("sha256", hash(bytes))
  end

  defp region(bytes, offset) do
    %{"offset" => offset, "length" => byte_size(bytes), "sha256" => hash(bytes)}
  end

  defp span_summary(nil), do: nil

  defp span_summary(span) do
    %{
      "member" => Atom.to_string(span.member),
      "offset" => span.offset,
      "length" => span.length
    }
  end

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)

  defp term_string({:error, code}), do: "error:#{code}"
  defp term_string(value), do: atom_string(value)

  defp json_term(nil), do: nil
  defp json_term(value) when is_boolean(value) or is_number(value) or is_binary(value), do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value) when is_list(value), do: Enum.map(value, &json_term/1)

  defp json_term(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_term(item)} end)
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonicalize(item)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value

  defp hash(bytes) when is_binary(bytes) do
    :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
  end
end
