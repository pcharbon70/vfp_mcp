defmodule VfpMcp.Milestone0.ContractTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Milestone0.Contract

  # specled covers:
  # - vfp_mcp.package.milestone_delivery
  # - vfp_mcp.package.excluded_operations
  # - vfp_mcp.package.capability_sequence

  test "every milestone outcome names an observable result and evidence" do
    outcomes = Contract.outcomes()

    assert Enum.map(outcomes, & &1.id) == [
             :physical_codec,
             :semantic_model,
             :native_fixtures,
             :targeted_edit_spike,
             :native_acceptance
           ]

    assert Enum.all?(outcomes, fn outcome ->
             is_binary(outcome.result) and outcome.result != "" and outcome.evidence != []
           end)
  end

  test "later runtime capabilities are explicitly deferred" do
    for capability <- Contract.excluded_capabilities() do
      assert Contract.capability_status(capability) == :deferred
    end

    assert Contract.capability_status(:physical_codec) == :not_declared

    refute Code.ensure_loaded?(VfpMcp.Server)
    refute Code.ensure_loaded?(VfpMcp.Writer)
    refute Code.ensure_loaded?(VfpMcp.Edit.Structure)
    assert Supervisor.which_children(VfpMcp.Supervisor) == []
  end
end
