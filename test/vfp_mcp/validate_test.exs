defmodule VfpMcp.ValidateTest do
  use ExUnit.Case, async: true

  alias VfpMcp.{Finding, Limits, SourceObject, Validate}

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.validation_findings

  test "publishes stable rule severities, impacts, and scopes" do
    rules = Validate.rule_matrix()

    assert rules.hierarchy_cycle == %{
             severity: :error,
             impact: :mutation_blocked,
             scope: :objects
           }

    assert rules.property_unsupported_literal == %{
             severity: :warning,
             impact: :preserved,
             scope: :line
           }

    assert rules.method_missing_endproc.severity == :error
    assert rules.semantic_vfp_version_undeclared.impact == :informational
    assert rules.hierarchy_object_name_missing.scope == :object
  end

  test "sorts by physical location, rule code, and semantic identity" do
    findings = [
      Finding.new(:z_rule, :warning, :preserved, "z", location: %{member: :fpt, offset: 1}),
      Finding.new(:b_rule, :warning, :preserved, "b", location: %{member: :dbf, offset: 9}),
      Finding.new(:a_rule, :warning, :preserved, "a", location: %{member: :dbf, offset: 9}),
      Finding.new(:record_rule, :error, :mutation_blocked, "record",
        location: %{record: 2, field: "PARENT"},
        evidence: %{record: 2}
      )
    ]

    assert {:ok, sorted} = Validate.finalize(findings, Limits.new!())
    assert Enum.map(sorted, & &1.code) == [:a_rule, :b_rule, :z_rule, :record_rule]
    assert sorted == Validate.finalize(findings, Limits.new!()) |> elem(1)
  end

  test "separates document eligibility from per-object eligibility" do
    warning = Finding.new(:preserved, :warning, :preserved, "preserved")

    local =
      Finding.new(:local, :error, :mutation_blocked, "local",
        location: %{record: 2, field: "PARENT"},
        evidence: %{record: 2}
      )

    assert Validate.document_eligibility([warning]) == :eligible
    assert Validate.document_eligibility([warning, local]) == {:blocked, [:local]}

    objects = [
      %SourceObject{record_index: 1, path: "Form/One"},
      %SourceObject{record_index: 2, path: "Form/Two"}
    ]

    [first, second] = Validate.apply_object_eligibility(objects, [warning, local])
    assert first.edit_eligibility == :eligible
    assert second.edit_eligibility == {:blocked, [:local]}
  end
end
