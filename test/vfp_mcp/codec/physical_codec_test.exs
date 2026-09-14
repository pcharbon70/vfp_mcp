defmodule VfpMcp.Codec.PhysicalCodecTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec
  alias VfpMcp.Codec.PhysicalSummary
  alias VfpMcp.{Document, Limits}
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.dbf_structure
  # - vfp_mcp.codec.memo_pointer
  # - vfp_mcp.codec.fpt_structure
  # - vfp_mcp.codec.memo_block
  # - vfp_mcp.codec.lossless_encoding
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.codec.parse_mixed_endian_pair
  # - vfp_mcp.codec.reject_invalid_memo
  # - vfp_mcp.read.immutable_snapshot
  # - vfp_mcp.read.validation_findings
  # - vfp_mcp.read.source_fidelity

  test "the public boundary returns a physical document with explicit text views" do
    built =
      PairBuilder.build(
        code_page: 0x03,
        records: [
          %{
            deleted?: false,
            values: %{
              "OBJNAME" => <<"Caf", 0xE9>>,
              "PROPERTIES" => {:memo, 1, <<"Caption = Caf", 0xE9>>}
            }
          }
        ]
      )

    assert {:ok, %Document{} = document} = Codec.parse_pair(built.snapshot)
    assert document.pair == built.snapshot.identity
    assert document.version == 9
    assert document.encoding == :windows_1252
    assert document.physical.raw == %{dbf: built.dbf, fpt: built.fpt}
    assert document.schema == document.physical.dbf.fields
    assert document.records == document.physical.dbf.records
    assert [object] = document.objects
    assert object.record_index == 0
    assert object.identity_fields.objname.value == "Café"

    assert Enum.map(document.physical.text_views, &{&1.source, &1.field, &1.text}) == [
             {:field, "OBJNAME", "Café        "},
             {:memo, "PROPERTIES", "Caption = Café"}
           ]

    assert Enum.all?(document.findings, &(&1.code == :semantic_identity_field_missing))
  end

  test "unsupported and invalid text remains available only as raw bytes" do
    unsupported = PairBuilder.build(code_page: 0x00)
    assert {:ok, document} = Codec.parse_pair(unsupported.snapshot)
    assert document.encoding == nil
    assert document.physical.text_views == []
    assert Enum.any?(document.findings, &(&1.code == :codec_unsupported_code_page))
    assert document.physical.raw.dbf == unsupported.dbf

    invalid =
      PairBuilder.build(
        code_page: 0x03,
        records: [
          %{
            deleted?: false,
            values: %{"OBJNAME" => <<"bad", 0x81>>, "PROPERTIES" => nil}
          }
        ]
      )

    assert {:ok, document} = Codec.parse_pair(invalid.snapshot)
    assert Enum.any?(document.findings, &(&1.code == :codec_invalid_text_bytes))
    [name_view] = document.physical.text_views
    assert name_view.text == nil
    assert name_view.raw_bytes == <<"bad", 0x81, "        ">>
  end

  test "parsed text limits fail before conversion" do
    built = PairBuilder.build()

    assert {:error, [finding]} =
             Codec.parse_pair(built.snapshot, limits: Limits.new!(parsed_text_bytes: 4))

    assert finding.code == :limit_parsed_text_bytes_exceeded
  end

  test "physical summaries are canonical, bounded, and content-free" do
    built =
      PairBuilder.build(
        dbf_header_opaque: <<0xAA, 0xBB>>,
        fpt_header_opaque: <<0xCC, 0xDD>>,
        dbf_trailing: <<0x1A, 0xEE>>,
        fpt_trailing: <<0xFF>>
      )

    assert {:ok, first} = Codec.parse_pair(built.snapshot)
    assert {:ok, second} = Codec.parse_pair(built.snapshot)
    assert first == second

    summary = PhysicalSummary.summarize(first)
    encoded = PhysicalSummary.encode(first)

    assert summary == PhysicalSummary.summarize(second)
    assert encoded == PhysicalSummary.encode(second)
    assert {:ok, ^summary} = Jason.decode(encoded)
    refute String.contains?(encoded, "Synthetic")
    refute String.contains?(encoded, "frmBasic")
    assert summary["pair"]["pair_sha256"] == built.snapshot.identity.pair_sha256
    assert summary["dbf"]["member"]["sha256"] == built.snapshot.identity.dbf.sha256
    assert summary["fpt"]["member"]["sha256"] == built.snapshot.identity.fpt.sha256
    assert summary["dbf"]["trailing_region"]["length"] == 2
    assert summary["fpt"]["trailing_region"]["length"] == 1
  end

  test "fatal FPT corruption produces no partial document" do
    built = PairBuilder.build()
    truncated = PairBuilder.malformed(built, {:truncate, :fpt, 13})

    assert {:error, [finding]} = Codec.parse_pair(truncated.snapshot)
    assert finding.code == :fpt_next_free_beyond_file
    refute match?({:ok, %Document{}}, Codec.parse_pair(truncated.snapshot))
  end

  test "expected encoding options are validated" do
    built = PairBuilder.build()

    assert {:ok, %Document{encoding: :windows_1252}} =
             Codec.parse_pair(built.snapshot, expected_encoding: :windows_1252)

    assert {:error, [%{code: :invalid_codec_options}]} =
             Codec.parse_pair(built.snapshot, expected_encoding: :utf8)
  end
end
