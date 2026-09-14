defmodule VfpMcp.Integration.Phase3SemanticCodecTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias VfpMcp.Codec
  alias VfpMcp.Codec.{Encoding, SemanticSummary}
  alias VfpMcp.{Limits, SourceObject}
  alias VfpMcp.Source.PairSnapshot
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.property_edit_scope
  # - vfp_mcp.codec.method_edit_scope
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.acceptance.codec_evidence
  # - vfp_mcp.acceptance.deterministic_test_vectors
  # - vfp_mcp.acceptance.run_phase3_semantic_suite
  # - vfp_mcp.protocol.sdk_boundary
  # - vfp_mcp.read.full_path_identity
  # - vfp_mcp.read.validation_findings
  # - vfp_mcp.read.source_fidelity

  test "generated SCX/SCT and VCX/VCT pairs match semantic manifests with exact provenance" do
    for kind <- [:scx, :vcx] do
      built = generated_pair(kind)
      assert {:ok, document} = Codec.parse_pair(built.snapshot)

      assert document.pair.kind == kind
      assert document.version == if(kind == :scx, do: 9, else: 6)
      assert document.encoding == :windows_1252
      assert length(document.semantic_records) == length(document.records)
      assert Enum.map(document.semantic_records, & &1.category) == expected_categories(kind)
      assert paths_by_record(document.objects) == expected_paths(kind)
      assert Enum.sort(Map.keys(document.path_index)) == expected_index_paths(kind)
      assert document.edit_eligibility == :eligible

      assert_identity_provenance(document, built)
      assert_text_provenance(document, built)

      summary = SemanticSummary.encode(document)
      assert summary == SemanticSummary.encode(document)
      assert byte_size(summary) < 50_000
      refute summary =~ "Semantic Caf"
      refute summary =~ "Frm/Main"
      refute summary =~ "PROCEDURE"
    end
  end

  test "semantic parsing preserves every record, memo, unsupported region, and opaque byte" do
    built = generated_pair(:scx)
    assert {:ok, document} = Codec.parse_pair(built.snapshot)

    dbf = document.physical.dbf
    fpt = document.physical.fpt

    assert dbf.header_bytes <> dbf.records_bytes <> dbf.trailing_bytes == built.dbf

    assert fpt.header_bytes <>
             fpt.pre_data_bytes <>
             fpt.allocation_bytes <>
             fpt.trailing_bytes == built.fpt

    for record <- document.records do
      assert binary_part(built.dbf, record.span.offset, record.span.length) == record.raw_bytes
    end

    for memo_ref <- fpt.memo_refs, memo_ref.resolution == :resolved do
      assert binary_part(built.fpt, memo_ref.payload_span.offset, memo_ref.payload_span.length) ==
               memo_ref.payload_bytes
    end

    assert Enum.map(document.semantic_records, & &1.record_index) ==
             Enum.map(document.records, & &1.index)

    grid = object_by_name(document, "Grid 50%")
    ole_ref = Enum.find(grid.memo_refs, &(&1.field == "OLE"))
    assert ole_ref.block_type == 7
    assert ole_ref.payload_bytes == <<0xD0, 0xCF, 0x11, 0xE0, 1, 2, 3, 4>>
    assert Enum.any?(document.findings, &(&1.code == :fpt_unknown_block_type))

    form = object_by_name(document, "Frm/Main")
    assert form.property_memo.line_ending == :crlf
    assert Enum.any?(form.properties, &(&1.kind == :comment))

    assert IO.iodata_to_binary(Enum.map(form.properties, & &1.raw_bytes)) ==
             form.property_memo.raw_bytes

    assert form.method_memo.raw_bytes == memo_payload(form, "METHODS")

    assert Enum.all?(form.methods, fn method ->
             binary_part(built.fpt, method.byte_span.offset, method.byte_span.length) ==
               method.raw_bytes
           end)
  end

  test "valid physical containers retain invalid semantic structures with stable findings" do
    built = invalid_semantic_pair()
    limits = Limits.new!(hierarchy_depth: 2)

    assert {:ok, first} = Codec.parse_pair(built.snapshot, limits: limits)
    assert {:ok, second} = Codec.parse_pair(built.snapshot, limits: limits)
    assert first == second
    assert SemanticSummary.encode(first) == SemanticSummary.encode(second)

    codes = Enum.map(first.findings, & &1.code)

    for expected <- [
          :hierarchy_duplicate_sibling,
          :hierarchy_path_canonicalization_collision,
          :hierarchy_parent_ambiguous,
          :hierarchy_parent_missing,
          :hierarchy_self_parent,
          :hierarchy_cycle,
          :hierarchy_incompatible_parent,
          :limit_hierarchy_depth_exceeded,
          :property_duplicate_assignment,
          :property_malformed_string,
          :property_unsupported_literal,
          :method_duplicate_name,
          :method_nested_procedure,
          :method_unmatched_endproc,
          :method_missing_endproc
        ] do
      assert expected in codes
    end

    assert {:blocked, _codes} = first.edit_eligibility
    refute Map.has_key?(first.path_index, "form/same")
    refute Map.has_key?(first.path_index, "form/mixed")

    form = object_by_name(first, "Form")
    assert {:blocked, _codes} = form.edit_eligibility
    assert form.property_memo.raw_bytes == memo_payload(form, "PROPERTIES")
    assert form.method_memo.raw_bytes == memo_payload(form, "METHODS")
    refute Enum.any?(form.methods, &(&1.name == "Fake"))

    assert first.physical.raw == %{dbf: built.dbf, fpt: built.fpt}
    assert length(first.semantic_records) == length(first.records)
  end

  test "equal snapshots remain structurally equal across concurrent locale contexts" do
    built = generated_pair(:vcx)

    results =
      ["en_CA", "fr_CA", "tr_TR", "C"]
      |> Enum.flat_map(fn locale -> List.duplicate(locale, 5) end)
      |> Enum.map(fn locale ->
        Task.async(fn ->
          Process.put(:phase3_test_locale, locale)
          Codec.parse_pair(built.snapshot)
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert length(Enum.uniq(results)) == 1
    [{:ok, document}] = Enum.uniq(results)

    summaries = Enum.map(results, fn {:ok, item} -> SemanticSummary.encode(item) end)
    assert Enum.uniq(summaries) == [SemanticSummary.encode(document)]
    refute contains_effect_handle?(document)
  end

  test "semantic orchestration emits nothing, spawns nothing, and ignores identity paths" do
    built = generated_pair(:vcx)
    dbf_path = Path.expand("_build/test/phase3-never-created.vcx")
    fpt_path = Path.expand("_build/test/phase3-never-created.vct")

    refute File.exists?(dbf_path)
    refute File.exists?(fpt_path)

    assert {:ok, snapshot} =
             PairSnapshot.new(:vcx, "phase3-side-effect-proof", built.dbf, built.fpt,
               declared_vfp_version: 6,
               dbf_path: dbf_path,
               fpt_path: fpt_path,
               dbf_modified_at: ~U[2026-09-14 10:00:00Z],
               fpt_modified_at: ~U[2026-09-14 10:00:00Z]
             )

    test_pid = self()
    :erlang.trace(test_pid, true, [:procs])
    result = Codec.parse_pair(snapshot)
    :erlang.trace(test_pid, false, [:procs])

    refute_receive {:trace, ^test_pid, :spawn, _pid, _mfa}, 10
    assert {:ok, document} = result
    assert document.pair.dbf.path == dbf_path
    assert document.pair.fpt.path == fpt_path
    refute File.exists?(dbf_path)
    refute File.exists?(fpt_path)

    assert capture_io(fn -> assert {:ok, _document} = Codec.parse_pair(snapshot) end) == ""

    assert capture_io(:stderr, fn ->
             assert {:ok, _document} = Codec.parse_pair(snapshot)
           end) == ""
  end

  defp generated_pair(:scx) do
    records = [
      source_record("COMMENT", "", "", "", reserved1: memo("opening bookend")),
      source_record("WINDOWS", "dataenvironment", "DataEnv", ""),
      source_record("WINDOWS", "cursor", "SyntheticCursor", "DataEnv"),
      source_record("WINDOWS", "form", "Frm/Main", "",
        properties:
          memo("Caption  =  \"Semantic Café\"\r\nWidth = 640\r\n* preserved comment\r\n"),
        methods: memo("PROCEDURE Init\r\n  value = \"ENDPROC\"\r\nENDPROC\r\n")
      ),
      source_record("WINDOWS", "pageframe", "Pages", "Frm/Main"),
      source_record("WINDOWS", "page", "Page One", "Pages"),
      source_record("WINDOWS", "grid", "Grid 50%", "Page One",
        properties: memo("ColumnCount = 1\r\n"),
        ole: {:memo, 7, <<0xD0, 0xCF, 0x11, 0xE0, 1, 2, 3, 4>>}
      ),
      source_record("WINDOWS", "column", "Column/A", "Grid 50%"),
      source_record("WINDOWS", "header", "Header One", "Column/A",
        properties: memo("Caption = \"Header\"\r\n")
      ),
      source_record("WINDOWS", "commandbutton", "Cmd Apply", "Page One",
        properties: memo("Caption = \"Apply\"\r\nEnabled = .T.\r\nStart = {^2026-09-14}\r\n"),
        methods: memo("PROCEDURE Click\r\n  ? \"Apply\"\r\nENDPROC\r\n")
      ),
      source_record("COMMENT", "", "", "", reserved1: memo("closing bookend"))
    ]

    PairBuilder.build(
      kind: :scx,
      source_id: "phase3-generated-form",
      declared_vfp_version: 9,
      fields: source_fields(),
      records: records,
      block_size: 64
    )
  end

  defp generated_pair(:vcx) do
    records = [
      source_record("COMMENT", "", "", "", reserved1: memo("opening class bookend")),
      source_record("WINDOWS", "container", "CaféWidget", "",
        class: memo("CaféWidget"),
        properties: memo("Width = 320\nHeight = 200\n"),
        methods: memo("procedure Reset\n  this.Value = .NULL.\nendproc\n")
      ),
      source_record("WINDOWS", "label", "Title Label", "CaféWidget",
        properties: memo("Caption = \"Synthetic\"\n")
      ),
      source_record("WINDOWS", "commandbutton", "Action%Button", "CaféWidget",
        methods: memo("PROCEDURE Click\n  ? \"ok\"\nENDPROC\n")
      ),
      source_record("COMMENT", "", "", "", reserved1: memo("closing class bookend"))
    ]

    PairBuilder.build(
      kind: :vcx,
      source_id: "phase3-generated-class-library",
      declared_vfp_version: 6,
      fields: source_fields(),
      records: records,
      block_size: 64
    )
  end

  defp invalid_semantic_pair do
    properties =
      memo("Caption = \"One\"\ncaption = \"Two\"\nBroken = \"unterminated\nCalc = =1 + 2\n")

    methods =
      memo(
        "* PROCEDURE Fake\nPROCEDURE Click\nENDPROC\nprocedure CLICK\nENDPROC\n" <>
          "PROCEDURE Outer\nPROCEDURE Inner\nENDPROC\nENDPROC\nPROCEDURE Lost\n"
      )

    records = [
      source_record("WINDOWS", "form", "Form", "", properties: properties, methods: methods),
      source_record("WINDOWS", "commandbutton", "Same", "Form"),
      source_record("WINDOWS", "commandbutton", "Same", "Form"),
      source_record("WINDOWS", "commandbutton", "Mixed", "Form"),
      source_record("WINDOWS", "commandbutton", "mixed", "Form"),
      source_record("WINDOWS", "commandbutton", "AmbiguousChild", "Same"),
      source_record("WINDOWS", "commandbutton", "Missing", "Absent"),
      source_record("WINDOWS", "container", "Self", "Self"),
      source_record("WINDOWS", "container", "CycleA", "CycleB"),
      source_record("WINDOWS", "container", "CycleB", "CycleA"),
      source_record("WINDOWS", "label", "Leaf", "Form"),
      source_record("WINDOWS", "commandbutton", "BadChild", "Leaf"),
      source_record("WINDOWS", "container", "Deep1", "Form"),
      source_record("WINDOWS", "container", "Deep2", "Deep1"),
      source_record("WINDOWS", "commandbutton", "Deep3", "Deep2")
    ]

    PairBuilder.build(
      kind: :scx,
      source_id: "phase3-invalid-semantics",
      declared_vfp_version: 9,
      fields: source_fields(),
      records: records,
      block_size: 64
    )
  end

  defp source_fields do
    [
      %{name: "PLATFORM", type: :character, length: 8},
      %{name: "UNIQUEID", type: :character, length: 10},
      %{name: "CLASS", type: :memo, length: 4},
      %{name: "CLASSLOC", type: :memo, length: 4},
      %{name: "BASECLASS", type: :memo, length: 4},
      %{name: "OBJNAME", type: :memo, length: 4},
      %{name: "PARENT", type: :memo, length: 4},
      %{name: "PROPERTIES", type: :memo, length: 4},
      %{name: "PROTECTED", type: :memo, length: 4},
      %{name: "METHODS", type: :memo, length: 4},
      %{name: "OBJCODE", type: :memo, length: 4},
      %{name: "OLE", type: :memo, length: 4},
      %{name: "OLE2", type: :memo, length: 4},
      %{name: "RESERVED1", type: :memo, length: 4},
      %{name: "USER", type: :memo, length: 4}
    ]
  end

  defp source_record(platform, baseclass, objname, parent, opts \\ []) do
    values = %{
      "PLATFORM" => platform,
      "UNIQUEID" => Keyword.get(opts, :uniqueid, ""),
      "CLASS" => Keyword.get(opts, :class),
      "CLASSLOC" => Keyword.get(opts, :classloc),
      "BASECLASS" => optional_memo(baseclass),
      "OBJNAME" => optional_memo(objname),
      "PARENT" => optional_memo(parent),
      "PROPERTIES" => Keyword.get(opts, :properties),
      "PROTECTED" => Keyword.get(opts, :protected),
      "METHODS" => Keyword.get(opts, :methods),
      "OBJCODE" => Keyword.get(opts, :objcode),
      "OLE" => Keyword.get(opts, :ole),
      "OLE2" => Keyword.get(opts, :ole2),
      "RESERVED1" => Keyword.get(opts, :reserved1),
      "USER" => Keyword.get(opts, :user)
    }

    %{deleted?: Keyword.get(opts, :deleted?, false), values: values}
  end

  defp optional_memo(""), do: nil
  defp optional_memo(value), do: memo(value)

  defp memo(text) do
    {:ok, bytes} = Encoding.encode(text, :windows_1252)
    {:memo, 1, bytes}
  end

  defp expected_categories(:scx) do
    [
      :bookend_open,
      :data_environment,
      :data_environment_entry,
      :object,
      :object,
      :object,
      :object,
      :object,
      :object,
      :object,
      :bookend_close
    ]
  end

  defp expected_categories(:vcx) do
    [:bookend_open, :object, :object, :object, :bookend_close]
  end

  defp expected_paths(:scx) do
    %{
      3 => "Frm%2FMain",
      4 => "Frm%2FMain/Pages",
      5 => "Frm%2FMain/Pages/Page%20One",
      6 => "Frm%2FMain/Pages/Page%20One/Grid%2050%25",
      7 => "Frm%2FMain/Pages/Page%20One/Grid%2050%25/Column%2FA",
      8 => "Frm%2FMain/Pages/Page%20One/Grid%2050%25/Column%2FA/Header%20One",
      9 => "Frm%2FMain/Pages/Page%20One/Cmd%20Apply"
    }
  end

  defp expected_paths(:vcx) do
    %{
      1 => "Caf%C3%A9Widget",
      2 => "Caf%C3%A9Widget/Title%20Label",
      3 => "Caf%C3%A9Widget/Action%25Button"
    }
  end

  defp expected_index_paths(kind),
    do: kind |> expected_paths() |> Map.values() |> Enum.map(&canonical_path/1) |> Enum.sort()

  defp canonical_path(path) do
    {:ok, canonical} = VfpMcp.Source.Path.canonicalize(path)
    canonical
  end

  defp paths_by_record(objects), do: Map.new(objects, &{&1.record_index, &1.path})

  defp assert_identity_provenance(document, built) do
    for object <- document.objects,
        {_name, value} <- object.identity_fields do
      source = if value.span.member == :dbf, do: built.dbf, else: built.fpt
      assert binary_part(source, value.span.offset, value.span.length) == value.raw_bytes
      assert value.field_index >= 0

      if value.memo_ref do
        assert value.memo_ref.record_index == object.record_index
        assert value.memo_ref.field == value.field
        assert value.memo_ref.pointer_span.member == :dbf
      end
    end
  end

  defp assert_text_provenance(document, built) do
    for object <- document.objects,
        property <- object.properties do
      assert binary_part(built.fpt, property.byte_span.offset, property.byte_span.length) ==
               property.raw_bytes
    end

    for object <- document.objects,
        method <- object.methods do
      assert binary_part(built.fpt, method.byte_span.offset, method.byte_span.length) ==
               method.raw_bytes
    end
  end

  defp object_by_name(document, name) do
    Enum.find(document.objects, fn object -> object.identity_fields.objname.value == name end)
  end

  defp memo_payload(%SourceObject{} = object, field) do
    object.memo_refs
    |> Enum.find(&(&1.field == field))
    |> Map.fetch!(:payload_bytes)
  end

  defp contains_effect_handle?(term)
       when is_pid(term) or is_port(term) or is_reference(term) or is_function(term),
       do: true

  defp contains_effect_handle?(term) when is_map(term) do
    values = if is_struct(term), do: Map.from_struct(term), else: term
    values |> Map.values() |> Enum.any?(&contains_effect_handle?/1)
  end

  defp contains_effect_handle?(term) when is_list(term),
    do: Enum.any?(term, &contains_effect_handle?/1)

  defp contains_effect_handle?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&contains_effect_handle?/1)

  defp contains_effect_handle?(_term), do: false
end
