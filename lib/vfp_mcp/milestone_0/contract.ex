defmodule VfpMcp.Milestone0.Contract do
  @moduledoc """
  Executable scope contract for the codec and acceptance spike.

  This module describes evidence-bearing outcomes and hard exclusions. It does
  not expose a runtime capability or make completion claims.
  """

  # specled covers:
  # - vfp_mcp.package.milestone_delivery
  # - vfp_mcp.package.excluded_operations
  # - vfp_mcp.package.capability_sequence

  @type outcome_id ::
          :physical_codec
          | :semantic_model
          | :native_fixtures
          | :targeted_edit_spike
          | :native_acceptance

  @type evidence_type ::
          :automated_tests
          | :byte_fidelity
          | :fixture_review
          | :hash_bound_json
          | :human_signoff
          | :native_vfp

  @type outcome :: %{
          id: outcome_id(),
          result: String.t(),
          evidence: [evidence_type()]
        }

  @type excluded_capability ::
          :application_data_access
          | :ide_automation
          | :mcp_tools
          | :production_transactions
          | :structural_editing
          | :vfp_execution

  @outcomes [
    %{
      id: :physical_codec,
      result: "bounds-checked DBF/FPT physical model with retained source bytes",
      evidence: [:automated_tests, :byte_fidelity]
    },
    %{
      id: :semantic_model,
      result: "properties, named methods, object paths, containment, and findings",
      evidence: [:automated_tests, :byte_fidelity]
    },
    %{
      id: :native_fixtures,
      result: "independently authored and reviewed synthetic VFP 6 and VFP 9 pairs",
      evidence: [:fixture_review, :hash_bound_json, :human_signoff]
    },
    %{
      id: :targeted_edit_spike,
      result: "pure property and named-method edit plans with exact byte footprints",
      evidence: [:automated_tests, :byte_fidelity]
    },
    %{
      id: :native_acceptance,
      result: "recorded VFP 6 and VFP 9 behavior for the targeted edit classes",
      evidence: [:hash_bound_json, :human_signoff, :native_vfp]
    }
  ]

  @excluded_capabilities [
    :application_data_access,
    :ide_automation,
    :mcp_tools,
    :production_transactions,
    :structural_editing,
    :vfp_execution
  ]

  @spec outcomes() :: [outcome()]
  def outcomes, do: @outcomes

  @spec excluded_capabilities() :: [excluded_capability()]
  def excluded_capabilities, do: @excluded_capabilities

  @spec capability_status(atom()) :: :deferred | :not_declared
  def capability_status(capability) when capability in @excluded_capabilities, do: :deferred
  def capability_status(_capability), do: :not_declared
end
