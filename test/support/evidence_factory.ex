defmodule VfpMcp.TestSupport.EvidenceFactory do
  @moduledoc false

  @hash_a String.duplicate("a", 64)
  @hash_b String.duplicate("b", 64)
  @hash_c String.duplicate("c", 64)

  def valid_record(overrides \\ %{}) do
    base = %{
      "schema_version" => 1,
      "evidence_id" => "vfp9-fixture-authoring-basic-form",
      "scenario_id" => "fixture_authoring",
      "vfp_version" => 9,
      "ide_version" => "Microsoft Visual FoxPro 9.0",
      "operator" => "Fixture Author",
      "recorded_at" => "2026-09-14T12:00:00Z",
      "outcome" => "pass",
      "source_pair" => pair("basic_form", "scx", @hash_a),
      "result_pair" => nil,
      "actions" =>
        Enum.map(~w(create save close hash review), fn id ->
          %{"id" => id, "outcome" => "pass", "observation" => "#{id} completed"}
        end),
      "observations" => %{"dependencies" => "none", "synthetic_content" => true},
      "signoff_file" => "signoff.md"
    }

    Map.merge(base, overrides)
  end

  def valid_signoff(record) do
    source_hash = get_in(record, ["source_pair", "pair_sha256"])
    result_hash = get_in(record, ["result_pair", "pair_sha256"]) || "none"

    """
    <!-- vfp-mcp-native-signoff:v1 -->
    # Native Evidence Signoff

    - Evidence ID: `#{record["evidence_id"]}`
    - Source pair SHA-256: `#{source_hash}`
    - Result pair SHA-256: `#{result_hash}`
    - Reviewer: `Fixture Reviewer`
    - Reviewed at: `2026-09-14T13:00:00Z`

    - [x] Both source-pair members are present and match the JSON hashes.
    - [x] Content is synthetic and contains no proprietary or identifying material.
    - [x] No database, table, connection, executable, or production path is present.
    - [x] No external class or application dependency is present.
    - [x] Required native actions and observations are recorded accurately.
    - [x] Anomalies and failed actions are recorded without waiver.
    """
  end

  def pair(base, kind, pair_hash) do
    {dbf_extension, fpt_extension} = if kind == "scx", do: {"scx", "sct"}, else: {"vcx", "vct"}

    %{
      "kind" => kind,
      "pair_sha256" => pair_hash,
      "dbf" => %{"name" => "#{base}.#{dbf_extension}", "sha256" => @hash_b, "bytes" => 128},
      "fpt" => %{"name" => "#{base}.#{fpt_extension}", "sha256" => @hash_c, "bytes" => 512}
    }
  end
end
