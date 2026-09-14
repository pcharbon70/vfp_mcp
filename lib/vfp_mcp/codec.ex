defmodule VfpMcp.Codec do
  @moduledoc """
  Pure public boundary for parsing an immutable Visual FoxPro source pair.

  The physical stage produces a loss-aware DBF/FPT model and explicit text
  views. The semantic stage classifies every record and builds conservative
  objects without reading paths or introducing process state.
  """

  # specled covers:
  # - vfp_mcp.codec.dbf_structure
  # - vfp_mcp.codec.memo_pointer
  # - vfp_mcp.codec.fpt_structure
  # - vfp_mcp.codec.memo_block
  # - vfp_mcp.codec.lossless_encoding
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.immutable_snapshot
  # - vfp_mcp.read.validation_findings
  # - vfp_mcp.read.source_fidelity
  # - vfp_mcp.protocol.sdk_boundary

  alias VfpMcp.Codec.{Dbf, Encoding, Fpt, Methods, Properties, Semantic, Tree}
  alias VfpMcp.{Document, Finding, Limits, Validate}
  alias VfpMcp.Source.PairSnapshot

  @type option :: {:limits, Limits.t()} | {:expected_encoding, Encoding.encoding() | nil}
  @type result :: {:ok, Document.t()} | {:error, [Finding.t()]}

  @doc """
  Validates an immutable pair snapshot and decodes its physical members.

  On eventual success, non-fatal findings belong to `Document.findings`. An
  error tuple contains fatal findings only. No branch reads paths or emits MCP
  values.
  """
  @spec parse_pair(PairSnapshot.t(), [option()]) :: result()
  def parse_pair(snapshot, opts \\ [])

  def parse_pair(%PairSnapshot{} = snapshot, opts) when is_list(opts) do
    with :ok <- PairSnapshot.validate(snapshot),
         {:ok, limits, expected_encoding} <- options(opts),
         :ok <- check_member(limits, :dbf, snapshot.dbf_bytes),
         :ok <- check_member(limits, :fpt, snapshot.fpt_bytes),
         {:ok, dbf, dbf_findings} <- Dbf.decode(snapshot.dbf_bytes, limits),
         {:ok, fpt, fpt_findings} <- Fpt.decode(snapshot.fpt_bytes, dbf, limits),
         {:ok, encoding, encoding_findings} <-
           Encoding.resolve(dbf.header.code_page, expected_encoding),
         {:ok, text_views, text_findings} <-
           Encoding.decode_physical(dbf, fpt, encoding, limits),
         {:ok, semantic_records, objects, data_environment, semantic_findings} <-
           Semantic.build(dbf, fpt, text_views),
         {:ok, objects, property_findings} <-
           Properties.attach(objects, text_views, encoding),
         {:ok, objects, method_findings} <- Methods.attach(objects, text_views, encoding),
         {:ok, objects, tree, path_index, hierarchy_findings} <- Tree.build(objects, limits),
         {:ok, findings} <-
           Validate.finalize(
             dbf_findings ++
               fpt_findings ++
               encoding_findings ++
               text_findings ++
               semantic_findings ++
               property_findings ++
               method_findings ++
               hierarchy_findings ++
               compatibility_findings(snapshot, dbf),
             limits
           ) do
      edit_eligibility = Validate.document_eligibility(findings)
      objects = Validate.apply_object_eligibility(objects, findings)
      path_index = refresh_path_index(path_index, objects)

      {:ok,
       %Document{
         pair: snapshot.identity,
         physical: %{
           dbf: dbf,
           fpt: fpt,
           text_views: text_views,
           raw: %{dbf: snapshot.dbf_bytes, fpt: snapshot.fpt_bytes}
         },
         version: snapshot.identity.declared_vfp_version,
         encoding: encoding,
         schema: dbf.fields,
         records: dbf.records,
         semantic_records: semantic_records,
         objects: objects,
         data_environment: data_environment,
         tree: tree,
         path_index: path_index,
         inspectability: :inspectable,
         edit_eligibility: edit_eligibility,
         findings: findings
       }}
    else
      {:error, %Finding{} = finding} ->
        {:error, [finding]}

      {:error, [%Finding{} | _] = findings} ->
        {:error, findings}

      {:error, :invalid_codec_options} ->
        {:error, [Finding.fatal(:invalid_codec_options, "codec options are invalid")]}

      {:error, reason} ->
        {:error,
         [
           Finding.fatal(:invalid_pair_snapshot, "pair snapshot validation failed",
             evidence: %{reason: reason}
           )
         ]}
    end
  end

  def parse_pair(_snapshot, _opts) do
    {:error, [Finding.fatal(:invalid_pair_snapshot, "expected a complete PairSnapshot")]}
  end

  defp options(opts) do
    case Keyword.validate(opts, limits: Limits.new!(), expected_encoding: nil) do
      {:ok, validated} ->
        case {Keyword.fetch!(validated, :limits), Keyword.fetch!(validated, :expected_encoding)} do
          {%Limits{} = limits, expected} when expected in [nil, :windows_1252] ->
            {:ok, limits, expected}

          _invalid ->
            {:error, :invalid_codec_options}
        end

      {:error, _unknown} ->
        {:error, :invalid_codec_options}
    end
  end

  defp check_member(limits, member, bytes) do
    Limits.check(limits, :member_bytes, byte_size(bytes), %{member: member, offset: 0})
  end

  defp refresh_path_index(path_index, objects) do
    objects_by_record = Map.new(objects, &{&1.record_index, &1})

    Map.new(path_index, fn {path, object} ->
      {path, Map.fetch!(objects_by_record, object.record_index)}
    end)
  end

  defp compatibility_findings(snapshot, dbf) do
    version_findings =
      if is_nil(snapshot.identity.declared_vfp_version) do
        [
          Finding.new(
            :semantic_vfp_version_undeclared,
            :info,
            :informational,
            "caller did not declare a VFP 6 or VFP 9 compatibility target"
          )
        ]
      else
        []
      end

    format_findings =
      if dbf.header.format == 0x30 do
        []
      else
        [
          Finding.new(
            :semantic_dbf_format_unsupported,
            :error,
            :mutation_blocked,
            "DBF format metadata is not the supported Visual FoxPro format",
            location: %{member: :dbf, offset: 0},
            evidence: %{format: dbf.header.format}
          )
        ]
      end

    version_findings ++ format_findings
  end
end
