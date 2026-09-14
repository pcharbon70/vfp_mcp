defmodule VfpMcp.Codec do
  @moduledoc """
  Pure public boundary for parsing an immutable Visual FoxPro source pair.

  Phase 1 validates identity, options, and pre-parse member limits. The physical
  decoder is intentionally unavailable until Phase 2 and returns a stable fatal
  finding instead of fabricated semantic data.
  """

  # specled covers:
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.{Document, Finding, Limits}
  alias VfpMcp.Source.PairSnapshot

  @type option :: {:limits, Limits.t()}
  @type result :: {:ok, Document.t()} | {:error, [Finding.t()]}

  @doc """
  Validates an immutable pair snapshot and delegates to the physical codec.

  On eventual success, non-fatal findings belong to `Document.findings`. An
  error tuple contains fatal findings only. No branch reads paths or emits MCP
  values.
  """
  @spec parse_pair(PairSnapshot.t(), [option()]) :: result()
  def parse_pair(snapshot, opts \\ [])

  def parse_pair(%PairSnapshot{} = snapshot, opts) when is_list(opts) do
    with :ok <- PairSnapshot.validate(snapshot),
         {:ok, limits} <- limits_from_options(opts),
         :ok <- check_member(limits, :dbf, snapshot.dbf_bytes),
         :ok <- check_member(limits, :fpt, snapshot.fpt_bytes) do
      {:error,
       [
         Finding.fatal(
           :codec_not_implemented,
           "physical DBF/FPT decoding begins in Milestone 0 Phase 2"
         )
       ]}
    else
      {:error, %Finding{} = finding} ->
        {:error, [finding]}

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

  defp limits_from_options(opts) do
    case Keyword.validate(opts, limits: Limits.new!()) do
      {:ok, validated} ->
        case Keyword.fetch!(validated, :limits) do
          %Limits{} = limits -> {:ok, limits}
          _invalid -> {:error, :invalid_codec_options}
        end

      {:error, _unknown} ->
        {:error, :invalid_codec_options}
    end
  end

  defp check_member(limits, member, bytes) do
    Limits.check(limits, :member_bytes, byte_size(bytes), %{member: member, offset: 0})
  end
end
