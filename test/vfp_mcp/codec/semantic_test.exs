defmodule VfpMcp.Codec.SemanticTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec
  alias VfpMcp.Source.PairSnapshot
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.immutable_snapshot
  # - vfp_mcp.read.validation_findings
  # - vfp_mcp.read.source_fidelity
  # - vfp_mcp.protocol.sdk_boundary
  # - vfp_mcp.acceptance.deterministic_test_vectors
  # - vfp_mcp.acceptance.codec_evidence

  test "classifies every physical record and retains identity provenance" do
    built = semantic_pair()

    assert {:ok, document} = Codec.parse_pair(built.snapshot)
    assert document.pair.pair_sha256 == built.snapshot.identity.pair_sha256
    assert document.pair.dbf.sha256 == built.snapshot.identity.dbf.sha256
    assert document.pair.fpt.sha256 == built.snapshot.identity.fpt.sha256
    assert document.records == document.physical.dbf.records
    assert Enum.map(document.semantic_records, & &1.record_index) == Enum.to_list(0..4)

    assert Enum.map(document.semantic_records, & &1.category) == [
             :bookend_open,
             :data_environment,
             :object,
             :unknown,
             :bookend_close
           ]

    assert [object] = document.objects
    assert object.record_index == 2
    assert object.semantic_index == 2
    assert object.active? == false
    assert object.identity_fields.objname.value == "cmdApply"
    assert object.identity_fields.baseclass.value == "commandbutton"

    assert object.identity_fields.objname.span.member == :fpt
    assert object.identity_fields.objname.memo_ref.pointer_span.member == :dbf
    assert object.identity_fields.objname.raw_bytes == "cmdApply"
    assert Enum.any?(object.memo_refs, &(&1.field == "RESERVED1"))
    assert length(object.raw_fields) == length(document.schema)
    assert Enum.all?(object.spans, &(&1.length >= 0))
    assert object.property_memo.raw_bytes == "Caption = \"Apply\""
    assert [%{name: "Caption", value: "Apply"}] = object.properties
    assert object.method_memo.raw_bytes == "PROCEDURE Click\r\nENDPROC\r\n"
    assert [%{name: "Click", body: ""}] = object.methods
    assert object.path == "cmdApply"
    assert document.path_index["cmdapply"].edit_eligibility == :eligible
    assert document.tree.roots == [2]

    assert Enum.map(document.data_environment, & &1.record_index) == [1]
    assert document.inspectability == :inspectable
    assert document.edit_eligibility == :eligible
    assert document.findings == []
  end

  test "rejects companion extensions that contradict the declared pair kind" do
    built = semantic_pair()

    assert {:ok, snapshot} =
             PairSnapshot.new(:scx, "mixed-pair", built.dbf, built.fpt,
               declared_vfp_version: 9,
               dbf_path: "C:/isolated/form.scx",
               fpt_path: "C:/isolated/form.vct"
             )

    assert {:error, [finding]} = Codec.parse_pair(snapshot)
    assert finding.code == :invalid_pair_snapshot
    assert finding.severity == :fatal
    assert finding.evidence.reason == :pair_member_extension_mismatch
  end

  test "keeps bounded semantic problems inspectable and explicitly blocks edits" do
    built = semantic_pair(code_page: 0)

    assert {:ok, document} = Codec.parse_pair(built.snapshot)
    assert document.inspectability == :inspectable
    assert {:blocked, codes} = document.edit_eligibility
    assert :codec_unsupported_code_page in codes
    assert :semantic_identity_value_unavailable in codes
    assert document.physical.raw == %{dbf: built.dbf, fpt: built.fpt}
    assert length(document.semantic_records) == 5
  end

  test "fatal physical boundaries never expose a semantic document" do
    built = semantic_pair()
    truncated = binary_part(built.dbf, 0, 20)

    assert {:ok, snapshot} =
             PairSnapshot.new(:scx, "fatal-pair", truncated, built.fpt, declared_vfp_version: 9)

    assert {:error, [finding]} = Codec.parse_pair(snapshot)
    assert finding.code == :dbf_header_truncated
    assert finding.severity == :fatal
  end

  test "missing and duplicated identity descriptors are findings, never guesses" do
    fields = [
      %{name: "OBJNAME", type: :character, length: 12},
      %{name: "OBJNAME", type: :character, length: 12},
      %{name: "PROPERTIES", type: :memo, length: 4}
    ]

    built =
      PairBuilder.build(
        fields: fields,
        records: [
          %{values: %{"OBJNAME" => "ambiguous", "PROPERTIES" => nil}}
        ]
      )

    assert {:ok, document} = Codec.parse_pair(built.snapshot)
    [record] = document.semantic_records
    refute Map.has_key?(record.identity_fields, :objname)

    codes = Enum.map(document.findings, & &1.code)
    assert :dbf_duplicate_field_name in codes
    assert :semantic_identity_field_ambiguous in codes
    assert :semantic_identity_field_missing in codes
    assert match?({:blocked, _codes}, document.edit_eligibility)
  end

  defp semantic_pair(opts \\ []) do
    fields = [
      %{name: "PLATFORM", type: :character, length: 8},
      %{name: "UNIQUEID", type: :character, length: 10},
      %{name: "CLASS", type: :memo, length: 4},
      %{name: "CLASSLOC", type: :memo, length: 4},
      %{name: "BASECLASS", type: :memo, length: 4},
      %{name: "OBJNAME", type: :memo, length: 4},
      %{name: "PARENT", type: :memo, length: 4},
      %{name: "PROPERTIES", type: :memo, length: 4},
      %{name: "METHODS", type: :memo, length: 4},
      %{name: "RESERVED1", type: :memo, length: 4},
      %{name: "CUSTOM", type: :character, length: 5}
    ]

    records = [
      record("COMMENT", "", "", false, %{"RESERVED1" => memo("opening")}),
      record("WINDOWS", "dataenvironment", "DataEnv", false, %{}),
      record("WINDOWS", "commandbutton", "cmdApply", true, %{
        "CLASS" => memo("customButton"),
        "CLASSLOC" => memo("synthetic.vcx"),
        "PROPERTIES" => memo("Caption = \"Apply\""),
        "METHODS" => memo("PROCEDURE Click\r\nENDPROC\r\n"),
        "RESERVED1" => memo(<<1, 2, 3>>),
        "CUSTOM" => "raw"
      }),
      record("WINDOWS", "", "", false, %{"CUSTOM" => "kept"}),
      record("COMMENT", "", "", false, %{"RESERVED1" => memo("closing")})
    ]

    PairBuilder.build(Keyword.merge([fields: fields, records: records], opts))
  end

  defp record(platform, baseclass, objname, deleted?, overrides) do
    defaults = %{
      "PLATFORM" => platform,
      "UNIQUEID" => "",
      "CLASS" => nil,
      "CLASSLOC" => nil,
      "BASECLASS" => if(baseclass == "", do: nil, else: memo(baseclass)),
      "OBJNAME" => if(objname == "", do: nil, else: memo(objname)),
      "PARENT" => nil,
      "PROPERTIES" => nil,
      "METHODS" => nil,
      "RESERVED1" => nil,
      "CUSTOM" => ""
    }

    %{deleted?: deleted?, values: Map.merge(defaults, overrides)}
  end

  defp memo(text), do: {:memo, 1, text}
end
