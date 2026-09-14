defmodule VfpMcp.LimitsTest do
  use ExUnit.Case, async: true

  alias VfpMcp.{Finding, Limits}

  # specled covers:
  # - vfp_mcp.codec.pure_planning

  @expected_codes %{
    member_bytes: :limit_member_bytes_exceeded,
    records: :limit_records_exceeded,
    fields: :limit_fields_exceeded,
    memo_payload_bytes: :limit_memo_payload_bytes_exceeded,
    memo_blocks: :limit_memo_blocks_exceeded,
    findings: :limit_findings_exceeded,
    hierarchy_depth: :limit_hierarchy_depth_exceeded,
    parsed_text_bytes: :limit_parsed_text_bytes_exceeded
  }

  test "defaults are positive and every limit has a stable exceeded code" do
    limits = Limits.new!()
    assert MapSet.new(Limits.keys()) == MapSet.new(Map.keys(@expected_codes))

    for {key, code} <- @expected_codes do
      maximum = Map.fetch!(limits, key)
      assert is_integer(maximum) and maximum > 0
      assert :ok = Limits.check(limits, key, maximum)

      assert {:error, %Finding{} = finding} = Limits.check(limits, key, maximum + 1)
      assert finding.code == code
      assert finding.severity == :fatal
      assert finding.evidence == %{actual: maximum + 1, maximum: maximum}
    end
  end

  test "known positive overrides are accepted and invalid overrides are rejected" do
    assert {:ok, %Limits{records: 12, hierarchy_depth: 4}} =
             Limits.new(records: 12, hierarchy_depth: 4)

    assert {:error, :invalid_limits} = Limits.new(records: 0)
    assert {:error, :invalid_limits} = Limits.new(unknown: 1)

    assert_raise ArgumentError, fn -> Limits.new!(memo_blocks: -1) end
  end

  test "finding taxonomy distinguishes each supported impact" do
    assert %Finding{severity: :fatal, impact: :unreadable} =
             Finding.new(:bad_header, :fatal, :unreadable, "bad header")

    assert %Finding{severity: :error, impact: :mutation_blocked} =
             Finding.new(:duplicate_target, :error, :mutation_blocked, "duplicate target")

    assert %Finding{severity: :warning, impact: :preserved} =
             Finding.new(:unknown_memo, :warning, :preserved, "unknown memo")

    assert %Finding{severity: :info, impact: :informational} =
             Finding.new(:mixed_version, :info, :informational, "mixed version")
  end

  test "finding messages and evidence are bounded" do
    assert_raise ArgumentError, fn ->
      Finding.new(:large_message, :warning, :preserved, String.duplicate("x", 1_025))
    end

    assert_raise ArgumentError, fn ->
      Finding.new(:large_evidence, :warning, :preserved, "bounded",
        evidence: %{value: String.duplicate("x", 4_096)}
      )
    end
  end
end
