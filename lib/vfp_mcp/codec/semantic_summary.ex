defmodule VfpMcp.Codec.SemanticSummary do
  @moduledoc """
  Canonical, content-safe evidence summary for a semantic source document.

  Source identities, object paths, values, property literals, and method bodies
  are represented by SHA-256 hashes. Counts, categories, spans, eligibility,
  and finding metadata remain directly reviewable.
  """

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.acceptance.codec_evidence

  alias VfpMcp.Document

  @schema_version 1

  @spec summarize(Document.t()) :: map()
  def summarize(%Document{} = document) do
    %{
      "schema_version" => @schema_version,
      "pair" => %{
        "kind" => Atom.to_string(document.pair.kind),
        "pair_sha256" => document.pair.pair_sha256,
        "source_id_sha256" => hash(document.pair.source_id),
        "vfp_version" => document.version,
        "encoding" => atom_string(document.encoding)
      },
      "counts" => %{
        "physical_records" => length(document.records),
        "semantic_records" => length(document.semantic_records),
        "objects" => length(document.objects),
        "data_environment_entries" => length(document.data_environment),
        "paths" => map_size(document.path_index),
        "findings" => length(document.findings)
      },
      "semantic_records" => Enum.map(document.semantic_records, &record_summary/1),
      "objects" => Enum.map(document.objects, &object_summary/1),
      "tree" => tree_summary(document.tree),
      "path_index" => path_index_summary(document.path_index),
      "inspectability" => atom_string(document.inspectability),
      "edit_eligibility" => eligibility(document.edit_eligibility),
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

  defp record_summary(record) do
    %{
      "semantic_index" => record.semantic_index,
      "record_index" => record.record_index,
      "category" => Atom.to_string(record.category),
      "raw_record_sha256" => hash(record.physical_record.raw_bytes),
      "memo_references" => length(record.memo_refs)
    }
  end

  defp object_summary(object) do
    %{
      "semantic_index" => object.semantic_index,
      "record_index" => object.record_index,
      "active" => object.active?,
      "path_sha256" => nullable_hash(object.path),
      "parent_record_index" => object.parent_record_index,
      "identity" => identity_summary(object.identity_fields),
      "property_memo" => memo_summary(object.property_memo),
      "properties" => Enum.map(object.properties, &property_summary/1),
      "method_memo" => memo_summary(object.method_memo),
      "methods" => Enum.map(object.methods, &method_summary/1),
      "edit_eligibility" => eligibility(object.edit_eligibility)
    }
  end

  defp identity_summary(identity_fields) do
    Map.new(identity_fields, fn {key, value} ->
      {Atom.to_string(key),
       %{
         "value_sha256" => hash(value.value),
         "raw_sha256" => hash(value.raw_bytes),
         "span" => span(value.span),
         "memo_pointer" => if(value.memo_ref, do: value.memo_ref.pointer, else: nil)
       }}
    end)
  end

  defp memo_summary(nil), do: nil

  defp memo_summary(memo) do
    %{
      "raw_sha256" => hash(memo.raw_bytes),
      "span" => span(memo.span),
      "line_ending" => atom_string(memo.line_ending),
      "edit_eligibility" => eligibility(memo.edit_eligibility)
    }
  end

  defp property_summary(property) do
    %{
      "index" => property.index,
      "kind" => atom_string(property.kind),
      "name_sha256" => nullable_hash(property.name),
      "literal_kind" => atom_string(property.literal_kind),
      "raw_sha256" => hash(property.raw_bytes),
      "raw_literal_sha256" => nullable_hash(property.raw_literal),
      "byte_span" => span(property.byte_span),
      "text_span" => property.text_span,
      "edit_eligibility" => eligibility(property.edit_eligibility)
    }
  end

  defp method_summary(method) do
    %{
      "index" => method.index,
      "name_sha256" => hash(method.name),
      "raw_sha256" => hash(method.raw_bytes),
      "body_sha256" => hash(method.body_bytes),
      "byte_span" => span(method.byte_span),
      "text_span" => method.text_span,
      "edit_eligibility" => eligibility(method.edit_eligibility)
    }
  end

  defp tree_summary(tree) do
    %{
      "roots" => Map.get(tree, :roots, []),
      "children" =>
        tree
        |> Map.get(:children, %{})
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {parent, children} -> %{"parent" => parent, "children" => children} end)
    }
  end

  defp path_index_summary(path_index) do
    path_index
    |> Enum.map(fn {path, object} ->
      %{"path_sha256" => hash(path), "record_index" => object.record_index}
    end)
    |> Enum.sort_by(&{&1["path_sha256"], &1["record_index"]})
  end

  defp finding_summary(finding) do
    %{
      "code" => Atom.to_string(finding.code),
      "severity" => Atom.to_string(finding.severity),
      "impact" => Atom.to_string(finding.impact),
      "location" => json_term(finding.location),
      "evidence_sha256" => hash(:erlang.term_to_binary(finding.evidence))
    }
  end

  defp span(nil), do: nil

  defp span(span) do
    %{
      "member" => Atom.to_string(span.member),
      "offset" => span.offset,
      "length" => span.length
    }
  end

  defp eligibility(:eligible), do: "eligible"
  defp eligibility(nil), do: nil

  defp eligibility({:blocked, codes}) do
    %{"blocked" => Enum.map(codes, &Atom.to_string/1)}
  end

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)

  defp nullable_hash(nil), do: nil
  defp nullable_hash(value), do: hash(value)

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
