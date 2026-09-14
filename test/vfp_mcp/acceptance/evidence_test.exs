defmodule VfpMcp.Acceptance.EvidenceTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Acceptance.Evidence
  alias VfpMcp.Finding
  alias VfpMcp.TestSupport.EvidenceFactory

  # specled covers:
  # - vfp_mcp.acceptance.evidence_bundle_integrity
  # - vfp_mcp.acceptance.version_native_handoff
  # - vfp_mcp.acceptance.validate_evidence_bundle

  @valid_dir Path.expand("../../fixtures/evidence/valid", __DIR__)
  @invalid_dir Path.expand("../../fixtures/evidence/invalid", __DIR__)

  test "the committed passing sample validates and summarizes deterministically" do
    json = read_committed_fixture(Path.join(@valid_dir, "native-evidence.json"))
    markdown = read_committed_fixture(Path.join(@valid_dir, "native-evidence-signoff.md"))

    assert {:ok, record} = Evidence.decode_json(json)
    assert {:ok, summary} = Evidence.validate_bundle(record, markdown)
    assert summary["evidence_id"] == "vfp9-fixture-authoring-basic-form"
    assert summary["scenario_id"] == "fixture_authoring"
    assert summary["vfp_version"] == 9
    assert summary["source_pair_sha256"] == String.duplicate("a", 64)
    assert summary["result_pair_sha256"] == nil
    assert summary["actions"] == ~w(create save close hash review)

    assert Evidence.encode_json(record) == Evidence.encode_json(record)
  end

  test "the committed failing sample reports stable validation failures" do
    json = read_committed_fixture(Path.join(@invalid_dir, "native-evidence.json"))
    markdown = read_committed_fixture(Path.join(@invalid_dir, "native-evidence-signoff.md"))

    assert {:ok, record} = Evidence.decode_json(json)
    assert {:error, findings} = Evidence.validate_bundle(record, markdown)

    codes = MapSet.new(findings, & &1.code)
    assert :evidence_invalid_outcome in codes
    assert :evidence_invalid_timestamp in codes
    assert :evidence_incomplete_pair in codes
    assert :evidence_invalid_hash in codes
    assert :evidence_missing_action in codes
    assert :evidence_signoff_mismatch in codes
    assert :evidence_signoff_unchecked in codes
  end

  test "edit evidence requires a complete result pair and every native action" do
    record =
      EvidenceFactory.valid_record(%{
        "scenario_id" => "property_edit",
        "actions" => [
          %{"id" => "open", "outcome" => "pass", "observation" => "opened"}
        ]
      })

    assert {:error, findings} = Evidence.validate(record)
    codes = Enum.map(findings, & &1.code)
    assert :evidence_incomplete_pair in codes
    assert Enum.count(codes, &(&1 == :evidence_missing_action)) == 5
  end

  test "a passing record cannot hide a failed required action" do
    actions =
      Enum.map(~w(create save close hash review), fn id ->
        outcome = if id == "review", do: "fail", else: "pass"
        %{"id" => id, "outcome" => outcome, "observation" => "recorded"}
      end)

    record = EvidenceFactory.valid_record(%{"actions" => actions})

    assert {:error, [%Finding{code: :evidence_failed_required_action}]} =
             Evidence.validate(record)
  end

  test "signoff must bind the exact evidence and pair hashes" do
    record = EvidenceFactory.valid_record()

    mismatched =
      record
      |> EvidenceFactory.valid_signoff()
      |> String.replace(String.duplicate("a", 64), String.duplicate("d", 64))

    assert {:error, findings} = Evidence.validate_bundle(record, mismatched)
    assert Enum.any?(findings, &(&1.code == :evidence_signoff_mismatch))
  end

  test "JSON decoding rejects malformed and non-object roots" do
    assert {:error, [%Finding{code: :evidence_invalid_json}]} = Evidence.decode_json("{")
    assert {:error, [%Finding{code: :evidence_invalid_json_root}]} = Evidence.decode_json("[]")
  end

  test "malformed nested JSON values return findings instead of raising" do
    record =
      EvidenceFactory.valid_record(%{
        "source_pair" => "not a pair",
        "actions" => ["not an action"]
      })

    assert {:error, findings} = Evidence.validate_bundle(record, "not a signoff")
    assert Enum.any?(findings, &(&1.code == :evidence_incomplete_pair))
    assert Enum.any?(findings, &(&1.code == :evidence_invalid_action))
    assert Enum.any?(findings, &(&1.code == :evidence_invalid_signoff))
  end

  defp read_committed_fixture(path) do
    policy = Application.fetch_env!(:vfp_mcp, :test_isolation_policy)
    assert :ok = VfpMcp.Development.IsolationPolicy.authorize(policy, :committed_fixture, path)
    File.read!(path)
  end
end
