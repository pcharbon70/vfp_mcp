defmodule VfpMcp.Integration.Phase1FoundationsTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Acceptance.{Evidence, FixtureSafety}
  alias VfpMcp.Development.IsolationPolicy
  alias VfpMcp.TestSupport.{EvidenceFactory, PairBuilder}

  # specled covers:
  # - vfp_mcp.acceptance.no_live_dependencies
  # - vfp_mcp.acceptance.fixture_review
  # - vfp_mcp.acceptance.evidence_bundle_integrity
  # - vfp_mcp.acceptance.deterministic_test_vectors
  # - vfp_mcp.acceptance.phase1_safe_foundation
  # - vfp_mcp.acceptance.run_phase1_safe_suite

  test "the default workflow rejects unsafe roots and fixture dependencies" do
    policy = Application.fetch_env!(:vfp_mcp, :test_isolation_policy)

    unsafe_sources = [
      "test/fixtures/vfp9/../../../../LecoWin2/source/live.scx",
      "C:/Leco/vfp/LecoWin2/source/live.scx",
      "C:/Leco/vfp/sbt/source/live.scx"
    ]

    for source <- unsafe_sources do
      assert {:error, :source_outside_allowed_root} =
               IsolationPolicy.authorize(policy, :committed_fixture, source)
    end

    cases = [
      {%{safe_inventory() | fpt_member: nil}, :fixture_pair_incomplete},
      {%{safe_inventory() | data_bindings: ["orders.customer_id"]}, :fixture_data_binding},
      {%{safe_inventory() | class_locations: ["C:/application/classes/base.vcx"]},
       :fixture_external_classloc},
      {%{safe_inventory() | commands: ["USE production!customers"]}, :fixture_data_command},
      {%{safe_inventory() | path_references: ["\\\\server\\deployment"]}, :fixture_external_path}
    ]

    for {inventory, expected_code} <- cases do
      assert {:error, findings} = FixtureSafety.validate(inventory)
      assert Enum.any?(findings, &(&1.code == expected_code))
    end
  end

  test "fixed inputs reproduce pair bytes, findings, and serialized evidence" do
    options = [
      source_id: "phase1-reproducibility",
      block_size: 512,
      stored_block_size: 0,
      dbf_header_opaque: <<1, 2, 3>>,
      fpt_header_opaque: <<4, 5, 6>>,
      dbf_trailing: <<0x1A, 0x7F>>,
      fpt_trailing: <<0x7E>>
    ]

    first = PairBuilder.build(options)
    second = PairBuilder.build(options)

    assert first.dbf == second.dbf
    assert first.fpt == second.fpt
    assert first.snapshot.identity == second.snapshot.identity

    unsafe = %{safe_inventory() | data_bindings: ["orders.customer_id"]}
    assert FixtureSafety.validate(unsafe) == FixtureSafety.validate(unsafe)

    record = fixture_record(first.snapshot)
    assert Evidence.encode_json(record) == Evidence.encode_json(record)
    assert Evidence.validate(record) == Evidence.validate(record)
  end

  test "a complete edit package is bound to actual source and result bytes" do
    {record, signoff, artifacts} = edit_bundle()

    assert {:ok, first_summary} = Evidence.validate_bundle(record, signoff, artifacts)
    assert {:ok, second_summary} = Evidence.validate_bundle(record, signoff, artifacts)
    assert first_summary == second_summary
    assert first_summary["source_pair_sha256"] == artifacts.source_pair.identity.pair_sha256
    assert first_summary["result_pair_sha256"] == artifacts.result_pair.identity.pair_sha256
    assert first_summary["actions"] == ~w(open inspect save close reopen compile)
  end

  test "tampered and incomplete packages never produce an accepted summary" do
    {record, signoff, artifacts} = edit_bundle()

    tampered_result = generated_pair("Tampered", "phase1-result").snapshot

    cases = [
      {record, signoff, %{artifacts | result_pair: tampered_result}, :evidence_artifact_mismatch},
      {put_in(record, ["result_pair", "fpt"], nil), signoff, artifacts,
       :evidence_incomplete_pair},
      {%{record | "actions" => Enum.reject(record["actions"], &(&1["id"] == "compile"))}, signoff,
       artifacts, :evidence_missing_action},
      {record, String.replace(signoff, "- [x]", "- [ ]", global: false), artifacts,
       :evidence_signoff_unchecked}
    ]

    for {invalid_record, invalid_signoff, invalid_artifacts, expected_code} <- cases do
      assert {:error, findings} =
               Evidence.validate_bundle(invalid_record, invalid_signoff, invalid_artifacts)

      assert Enum.any?(findings, &(&1.code == expected_code))
    end
  end

  defp safe_inventory do
    %{
      kind: :scx,
      dbf_member: "phase1.scx",
      fpt_member: "phase1.sct",
      data_bindings: [],
      class_locations: [],
      commands: [],
      path_references: []
    }
  end

  defp fixture_record(snapshot) do
    EvidenceFactory.valid_record(%{
      "source_pair" => Evidence.pair_record(snapshot, "phase1.scx", "phase1.sct")
    })
  end

  defp edit_bundle do
    source = generated_pair("Original", "phase1-source").snapshot
    result = generated_pair("Edited", "phase1-result").snapshot

    actions =
      Enum.map(~w(open inspect save close reopen compile), fn id ->
        %{"id" => id, "outcome" => "pass", "observation" => "#{id} completed"}
      end)

    record =
      EvidenceFactory.valid_record(%{
        "evidence_id" => "phase1-property-edit",
        "scenario_id" => "property_edit",
        "source_pair" => Evidence.pair_record(source, "phase1.scx", "phase1.sct"),
        "result_pair" => Evidence.pair_record(result, "phase1.scx", "phase1.sct"),
        "actions" => actions
      })

    {record, EvidenceFactory.valid_signoff(record), %{source_pair: source, result_pair: result}}
  end

  defp generated_pair(caption, source_id) do
    PairBuilder.build(
      source_id: source_id,
      records: [
        %{
          deleted?: false,
          values: %{
            "OBJNAME" => "frmPhase1",
            "PROPERTIES" => {:memo, 1, "Caption = \"#{caption}\""}
          }
        }
      ]
    )
  end
end
