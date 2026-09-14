defmodule VfpMcp.Acceptance.FixtureAdmissionTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Acceptance.FixtureAdmission

  # specled covers:
  # - vfp_mcp.acceptance.raw_intake_quarantine
  # - vfp_mcp.acceptance.fixture_review
  # - vfp_mcp.acceptance.fixture_admission_protocol

  test "a fixture needs passing inventory and human review before admission" do
    admission = FixtureAdmission.new(9, "basic_form")

    assert admission.state == :dropped
    assert admission.drop_directory == ".vfp_mcp/fixture-drop/vfp9"
    assert admission.fixture_directory == "test/fixtures/vfp9"
    assert {:error, :invalid_transition} = FixtureAdmission.admit(admission, "manifest-1")

    assert {:ok, awaiting_review} =
             FixtureAdmission.record_inventory(admission, :pass, "inventory-1", [])

    assert awaiting_review.state == :awaiting_review
    assert {:error, :invalid_transition} = FixtureAdmission.admit(awaiting_review, "manifest-1")

    assert {:ok, approved} =
             FixtureAdmission.record_review(awaiting_review, :pass, "review-1", [])

    assert approved.state == :approved
    assert {:ok, admitted} = FixtureAdmission.admit(approved, "manifest-1")
    assert admitted.state == :admitted
    assert admitted.inventory_evidence_id == "inventory-1"
    assert admitted.review_evidence_id == "review-1"
    assert admitted.admission_manifest_id == "manifest-1"
  end

  test "an automated rejection is terminal and records findings" do
    admission = FixtureAdmission.new(6, "fixture_classes")

    assert {:ok, rejected} =
             FixtureAdmission.record_inventory(
               admission,
               :fail,
               "inventory-vfp6-1",
               ["external CLASSLOC"]
             )

    assert rejected.state == :rejected
    assert rejected.findings == ["external CLASSLOC"]

    assert {:error, :invalid_transition} =
             FixtureAdmission.record_review(rejected, :pass, "review-1", [])
  end

  test "a human rejection is terminal and cannot be promoted" do
    admission = FixtureAdmission.new(9, "grid_form")

    assert {:ok, awaiting_review} =
             FixtureAdmission.record_inventory(admission, :pass, "inventory-1", [])

    assert {:ok, rejected} =
             FixtureAdmission.record_review(
               awaiting_review,
               :fail,
               "review-1",
               ["unexplained identifying string"]
             )

    assert rejected.state == :rejected
    assert {:error, :invalid_transition} = FixtureAdmission.admit(rejected, "manifest-1")
  end

  test "transitions require evidence and explicit rejection findings" do
    dropped = FixtureAdmission.new(9, "basic_form")

    assert {:error, :evidence_id_required} =
             FixtureAdmission.record_inventory(dropped, :pass, "", [])

    assert {:error, :rejection_findings_required} =
             FixtureAdmission.record_inventory(dropped, :fail, "inventory-1", [])

    assert {:ok, awaiting_review} =
             FixtureAdmission.record_inventory(dropped, :pass, "inventory-1", [])

    assert {:error, :rejection_findings_required} =
             FixtureAdmission.record_review(awaiting_review, :fail, "review-1", [])
  end
end
