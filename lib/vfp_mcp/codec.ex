defmodule VfpMcp.Codec do
  @moduledoc """
  Pure public boundary for parsing an immutable Visual FoxPro source pair.

  Phase 2 produces a loss-aware physical DBF/FPT model and explicit text views.
  Semantic objects, properties, methods, and hierarchy remain Phase 3 work.
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

  alias VfpMcp.Codec.{Dbf, Encoding, Fpt}
  alias VfpMcp.{Document, Finding, Limits}
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
         {:ok, findings} <-
           collect_findings(
             dbf_findings ++ fpt_findings ++ encoding_findings ++ text_findings,
             limits
           ) do
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

  defp collect_findings(findings, limits) do
    findings =
      Enum.sort_by(findings, fn finding ->
        {Atom.to_string(finding.code), inspect(finding.location), inspect(finding.evidence)}
      end)

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
end
