defmodule VfpMcp.CodecContractTest do
  use ExUnit.Case, async: true

  alias VfpMcp.{Codec, Document, EditPlan, Finding, Limits, SourceObject}
  alias VfpMcp.EditPlan.Postcondition
  alias VfpMcp.Source.{MemoRef, PairSnapshot, Span}

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.immutable_snapshot

  test "pair snapshots have deterministic member and complete-pair identities" do
    opts = [
      declared_vfp_version: 9,
      dbf_path: "C:/fixtures/basic_form.scx",
      fpt_path: "C:/fixtures/basic_form.sct"
    ]

    assert {:ok, first} = PairSnapshot.new(:scx, "basic_form", <<1, 2>>, <<3, 4>>, opts)
    assert {:ok, second} = PairSnapshot.new(:scx, "basic_form", <<1, 2>>, <<3, 4>>, opts)
    assert first == second
    assert first.identity.kind == :scx
    assert first.identity.declared_vfp_version == 9
    assert first.identity.dbf.role == :dbf
    assert first.identity.dbf.byte_size == 2
    assert first.identity.fpt.role == :fpt
    assert byte_size(first.identity.dbf.sha256) == 64
    assert byte_size(first.identity.pair_sha256) == 64
    assert :ok = PairSnapshot.validate(first)

    assert {:ok, class_pair} = PairSnapshot.new(:vcx, "fixture_classes", <<1, 2>>, <<3, 4>>)
    refute class_pair.identity.pair_sha256 == first.identity.pair_sha256
  end

  test "pair snapshot creation rejects incomplete identity and pair shape" do
    assert {:error, :invalid_kind} = PairSnapshot.new(:dbf, "basic", <<>>, <<>>)
    assert {:error, :invalid_source_id} = PairSnapshot.new(:scx, "", <<>>, <<>>)
    assert {:error, :invalid_bytes} = PairSnapshot.new(:scx, "basic", :not_bytes, <<>>)

    assert {:error, :invalid_version} =
             PairSnapshot.new(:scx, "basic", <<>>, <<>>, declared_vfp_version: 8)
  end

  test "the parse boundary reports stable fatal findings without file access" do
    assert {:ok, snapshot} = PairSnapshot.new(:scx, "generated", <<1>>, <<2>>)

    assert {:error, [%Finding{} = finding]} = Codec.parse_pair(snapshot)
    assert finding.code == :codec_not_implemented
    assert finding.severity == :fatal
    assert finding.impact == :unreadable

    assert {:error, [%Finding{code: :invalid_pair_snapshot, severity: :fatal}]} =
             Codec.parse_pair(%{dbf_bytes: <<>>, fpt_bytes: <<>>})
  end

  test "the parse boundary rejects a tampered snapshot identity" do
    assert {:ok, snapshot} = PairSnapshot.new(:vcx, "generated", <<1>>, <<2>>)
    tampered = %{snapshot | dbf_bytes: <<9>>}

    assert {:error, [%Finding{} = finding]} = Codec.parse_pair(tampered)
    assert finding.code == :invalid_pair_snapshot
    assert finding.evidence == %{reason: :snapshot_identity_mismatch}

    malformed = %{snapshot | identity: nil}

    assert {:error, [%Finding{code: :invalid_pair_snapshot}]} = Codec.parse_pair(malformed)
  end

  test "the parse boundary rejects unknown or malformed options" do
    assert {:ok, snapshot} = PairSnapshot.new(:scx, "generated", <<1>>, <<2>>)

    assert {:error, [%Finding{code: :invalid_codec_options}]} =
             Codec.parse_pair(snapshot, unknown: true)

    assert {:error, [%Finding{code: :invalid_codec_options}]} =
             Codec.parse_pair(snapshot, limits: :unbounded)
  end

  test "member limits are enforced before physical decoding" do
    limits = Limits.new!(member_bytes: 2)
    assert {:ok, snapshot} = PairSnapshot.new(:scx, "generated", <<1, 2, 3>>, <<4>>)

    assert {:error, [%Finding{} = finding]} = Codec.parse_pair(snapshot, limits: limits)
    assert finding.code == :limit_member_bytes_exceeded
    assert finding.location == %{member: :dbf, offset: 0}
    assert finding.evidence == %{actual: 3, maximum: 2}
  end

  test "documents and edit plans retain physical provenance as pure data" do
    assert {:ok, snapshot} = PairSnapshot.new(:scx, "generated", <<0, 1>>, <<2, 3>>)

    pointer_span = Span.new(:dbf, 10, 4)
    payload_span = Span.new(:fpt, 520, 8)

    memo_ref = %MemoRef{
      field: "PROPERTIES",
      pointer: 1,
      pointer_bytes: <<1, 0, 0, 0>>,
      pointer_span: pointer_span,
      payload_span: payload_span,
      payload_bytes: "Caption = \"Old\""
    }

    object = %SourceObject{record_index: 0, path: "frmBasic", memo_refs: [memo_ref]}

    document = %Document{
      pair: snapshot.identity,
      physical: %{dbf: snapshot.dbf_bytes, fpt: snapshot.fpt_bytes},
      objects: [object],
      path_index: %{"frmBasic" => object}
    }

    postcondition = %Postcondition{
      kind: :property,
      target: %{object_path: "frmBasic", property: "Caption"},
      expected: "New"
    }

    plan = EditPlan.new(document.pair, postcondition)

    assert plan.source_identity.pair_sha256 == snapshot.identity.pair_sha256
    assert plan.postcondition == postcondition
    assert plan.dbf_patches == []
    assert plan.memo_appends == []
    assert plan.expected_footprint == %{dbf: [], fpt: []}
  end
end
