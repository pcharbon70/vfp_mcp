defmodule VfpMcp.Acceptance.FixtureAdmission do
  @moduledoc """
  Pure state machine for synthetic native fixture admission.

  The module records authorization to promote; it never copies, opens, executes,
  or compiles a fixture.
  """

  # specled covers:
  # - vfp_mcp.acceptance.raw_intake_quarantine
  # - vfp_mcp.acceptance.fixture_review
  # - vfp_mcp.acceptance.fixture_admission_protocol

  @enforce_keys [:version, :pair_id, :drop_directory, :fixture_directory, :state]
  defstruct [
    :version,
    :pair_id,
    :drop_directory,
    :fixture_directory,
    :state,
    :inventory_evidence_id,
    :review_evidence_id,
    :admission_manifest_id,
    findings: []
  ]

  @type state :: :dropped | :awaiting_review | :approved | :rejected | :admitted

  @type t :: %__MODULE__{
          version: 6 | 9,
          pair_id: String.t(),
          drop_directory: Path.t(),
          fixture_directory: Path.t(),
          state: state(),
          inventory_evidence_id: String.t() | nil,
          review_evidence_id: String.t() | nil,
          admission_manifest_id: String.t() | nil,
          findings: [String.t()]
        }

  @type transition_error ::
          :evidence_id_required
          | :invalid_transition
          | :manifest_id_required
          | :rejection_findings_required

  @spec new(6 | 9, String.t()) :: t()
  def new(version, pair_id) when version in [6, 9] and is_binary(pair_id) and pair_id != "" do
    label = "vfp#{version}"

    %__MODULE__{
      version: version,
      pair_id: pair_id,
      drop_directory: ".vfp_mcp/fixture-drop/#{label}",
      fixture_directory: "test/fixtures/#{label}",
      state: :dropped
    }
  end

  @spec record_inventory(t(), :pass | :fail, String.t(), [String.t()]) ::
          {:ok, t()} | {:error, transition_error()}
  def record_inventory(%__MODULE__{state: :dropped} = admission, :pass, evidence_id, [])
      when is_binary(evidence_id) and evidence_id != "" do
    {:ok,
     %{
       admission
       | state: :awaiting_review,
         inventory_evidence_id: evidence_id
     }}
  end

  def record_inventory(%__MODULE__{state: :dropped} = admission, :fail, evidence_id, findings)
      when is_binary(evidence_id) and evidence_id != "" and is_list(findings) and findings != [] do
    {:ok,
     %{
       admission
       | state: :rejected,
         inventory_evidence_id: evidence_id,
         findings: findings
     }}
  end

  def record_inventory(%__MODULE__{state: :dropped}, _outcome, "", _findings),
    do: {:error, :evidence_id_required}

  def record_inventory(%__MODULE__{state: :dropped}, :fail, _evidence_id, []),
    do: {:error, :rejection_findings_required}

  def record_inventory(%__MODULE__{}, _outcome, _evidence_id, _findings),
    do: {:error, :invalid_transition}

  @spec record_review(t(), :pass | :fail, String.t(), [String.t()]) ::
          {:ok, t()} | {:error, transition_error()}
  def record_review(%__MODULE__{state: :awaiting_review} = admission, :pass, evidence_id, [])
      when is_binary(evidence_id) and evidence_id != "" do
    {:ok, %{admission | state: :approved, review_evidence_id: evidence_id}}
  end

  def record_review(
        %__MODULE__{state: :awaiting_review} = admission,
        :fail,
        evidence_id,
        findings
      )
      when is_binary(evidence_id) and evidence_id != "" and is_list(findings) and findings != [] do
    {:ok,
     %{
       admission
       | state: :rejected,
         review_evidence_id: evidence_id,
         findings: findings
     }}
  end

  def record_review(%__MODULE__{state: :awaiting_review}, _outcome, "", _findings),
    do: {:error, :evidence_id_required}

  def record_review(%__MODULE__{state: :awaiting_review}, :fail, _evidence_id, []),
    do: {:error, :rejection_findings_required}

  def record_review(%__MODULE__{}, _outcome, _evidence_id, _findings),
    do: {:error, :invalid_transition}

  @spec admit(t(), String.t()) :: {:ok, t()} | {:error, transition_error()}
  def admit(%__MODULE__{state: :approved} = admission, manifest_id)
      when is_binary(manifest_id) and manifest_id != "" do
    {:ok, %{admission | state: :admitted, admission_manifest_id: manifest_id}}
  end

  def admit(%__MODULE__{state: :approved}, ""), do: {:error, :manifest_id_required}
  def admit(%__MODULE__{}, _manifest_id), do: {:error, :invalid_transition}
end
