defmodule VfpMcp.Finding do
  @moduledoc """
  Stable, bounded diagnostic returned by codec and planning boundaries.
  """

  # specled covers:
  # - vfp_mcp.codec.pure_planning

  @enforce_keys [:code, :severity, :impact, :message]
  defstruct [:code, :severity, :impact, :message, :location, evidence: %{}]

  @type severity :: :fatal | :error | :warning | :info
  @type impact :: :unreadable | :mutation_blocked | :preserved | :informational

  @type location ::
          nil
          | %{optional(:member) => :dbf | :fpt, optional(:offset) => non_neg_integer()}
          | %{optional(:record) => non_neg_integer(), optional(:field) => String.t()}
          | %{optional(:object_path) => String.t()}

  @type t :: %__MODULE__{
          code: atom(),
          severity: severity(),
          impact: impact(),
          message: String.t(),
          location: location(),
          evidence: map()
        }

  @severities [:fatal, :error, :warning, :info]
  @impacts [:unreadable, :mutation_blocked, :preserved, :informational]
  @max_message_bytes 1_024
  @max_evidence_entries 16
  @max_evidence_bytes 4_096

  @spec new(atom(), severity(), impact(), String.t(), keyword()) :: t()
  def new(code, severity, impact, message, opts \\ [])
      when is_atom(code) and severity in @severities and impact in @impacts and
             is_binary(message) and is_list(opts) do
    location = Keyword.get(opts, :location)
    evidence = Keyword.get(opts, :evidence, %{})

    validate_bounded!(message, evidence)

    %__MODULE__{
      code: code,
      severity: severity,
      impact: impact,
      message: message,
      location: location,
      evidence: evidence
    }
  end

  @spec fatal(atom(), String.t(), keyword()) :: t()
  def fatal(code, message, opts \\ []) do
    new(code, :fatal, :unreadable, message, opts)
  end

  defp validate_bounded!(message, evidence) do
    valid_evidence? =
      is_map(evidence) and map_size(evidence) <= @max_evidence_entries and
        byte_size(:erlang.term_to_binary(evidence)) <= @max_evidence_bytes

    if byte_size(message) > @max_message_bytes or not valid_evidence? do
      raise ArgumentError, "finding message or evidence exceeds its bounded contract"
    end
  end
end
