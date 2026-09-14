defmodule VfpMcp.Codec.DbfTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.Dbf
  alias VfpMcp.Limits
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.dbf_structure
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  test "decodes header values, descriptor metadata, and exact source spans" do
    built =
      PairBuilder.build(
        code_page: 0x03,
        dbf_header_opaque: <<0xAA, 0xBB>>,
        fields: [
          %{name: "PROPERTIES", type: :memo, length: 4},
          %{name: "OBJNAME", type: :character, length: 10}
        ],
        records: [
          %{
            deleted?: false,
            values: %{"PROPERTIES" => nil, "OBJNAME" => "frmHeader"}
          }
        ]
      )

    assert {:ok, dbf, []} = Dbf.decode(built.dbf)
    assert dbf.header.format == 0x30
    assert dbf.header.date_bytes == <<0, 0, 0>>
    assert dbf.header.record_count == 1
    assert dbf.header.header_length == built.layout.header_length
    assert dbf.header.record_length == 15
    assert dbf.header.code_page == 0x03
    assert dbf.header.reserved_bytes.middle |> binary_part(0, 2) == <<0xAA, 0xBB>>
    assert dbf.header.spans.record_count == span(:dbf, 4, 4)
    assert dbf.header.spans.header_length == span(:dbf, 8, 2)
    assert dbf.header.spans.record_length == span(:dbf, 10, 2)
    assert dbf.header.spans.code_page == span(:dbf, 29, 1)

    [memo, name] = dbf.fields

    assert {memo.index, memo.name, memo.type, memo.length, memo.record_offset} ==
             {0, "PROPERTIES", :memo, 4, 1}

    assert memo.raw_name == <<"PROPERTIES", 0>>
    assert memo.address_bytes == <<0, 0, 0, 0>>
    assert memo.decimal_count == 0
    assert memo.flags == 0
    assert memo.reserved_bytes == :binary.copy(<<0>>, 13)
    assert memo.descriptor_span == span(:dbf, 32, 32)

    assert {name.index, name.name, name.type, name.length, name.record_offset} ==
             {1, "OBJNAME", :character, 10, 5}

    assert dbf.terminator_span == span(:dbf, built.layout.header_length - 1, 1)
    assert dbf.header_extension_bytes == <<>>
    assert dbf.header_bytes == binary_part(built.dbf, 0, built.layout.header_length)
  end

  test "retains active and deleted records with raw fixed-width values" do
    built =
      PairBuilder.build(
        fields: [
          %{name: "OBJNAME", type: :character, length: 8},
          %{name: "METHODS", type: :memo, length: 4}
        ],
        records: [
          %{deleted?: false, values: %{"OBJNAME" => "active", "METHODS" => nil}},
          %{deleted?: true, values: %{"OBJNAME" => "deleted", "METHODS" => nil}}
        ]
      )

    assert {:ok, dbf, []} = Dbf.decode(built.dbf)

    assert Enum.map(dbf.records, &{&1.index, &1.marker, &1.deleted?}) ==
             [{0, 0x20, false}, {1, 0x2A, true}]

    [active, deleted] = dbf.records
    assert active.raw_bytes == binary_part(built.dbf, active.span.offset, active.span.length)
    assert deleted.raw_bytes == binary_part(built.dbf, deleted.span.offset, deleted.span.length)

    [active_name, active_memo] = active.values
    assert active_name.raw_bytes == "active  "
    assert active_name.span == span(:dbf, built.layout.records_offset + 1, 8)
    assert active_memo.raw_bytes == <<0::unsigned-little-32>>
    assert active_memo.span == span(:dbf, built.layout.records_offset + 9, 4)
  end

  test "preserves unusual trailing bytes and unsupported fields" do
    built = PairBuilder.build(dbf_trailing: <<0x1A, 0xEE, 0xFF>>)
    type_offset = 32 + 11
    patched = replace(built.dbf, type_offset, <<?X>>)

    assert {:ok, dbf, findings} = Dbf.decode(patched)
    assert hd(dbf.fields).type == :opaque
    assert hd(dbf.fields).type_byte == ?X
    assert dbf.trailing_bytes == <<0x1A, 0xEE, 0xFF>>
    assert finding_codes(findings) == [:dbf_trailing_bytes_preserved, :dbf_unknown_field_type]
    assert binary_part(dbf.bytes, type_offset, 1) == <<?X>>
  end

  test "reports duplicate fields and invalid record markers without discarding bytes" do
    built = PairBuilder.build()
    first_name = binary_part(built.dbf, 32, 11)

    patched =
      built.dbf
      |> replace(64, first_name)
      |> replace(built.layout.records_offset, <<0x7F>>)

    assert {:ok, dbf, findings} = Dbf.decode(patched)
    assert Enum.map(dbf.fields, & &1.name) == ["OBJNAME", "OBJNAME"]
    assert hd(dbf.records).deleted? == nil
    assert hd(dbf.records).marker == 0x7F
    assert finding_codes(findings) == [:dbf_duplicate_field_name, :dbf_invalid_record_marker]
  end

  test "rejects invalid schema before decoding record fields" do
    built = PairBuilder.build()

    cases = [
      {replace(built.dbf, 32 + 16, <<0>>), :dbf_field_zero_length},
      {replace(built.dbf, 10, <<255::unsigned-little-16>>), :dbf_record_extent_invalid},
      {replace(built.dbf, built.layout.header_length - 1, <<0>>), :dbf_descriptor_truncated},
      {replace(built.dbf, 10, <<6::unsigned-little-16>>), :dbf_schema_width_exceeded}
    ]

    for {bytes, expected_code} <- cases do
      assert {:error, [finding]} = Dbf.decode(bytes)
      assert finding.code == expected_code
      assert finding.severity == :fatal
    end
  end

  test "truncated headers and impossible extents return findings without raising" do
    built = PairBuilder.build()

    for length <- 0..31 do
      bytes = binary_part(built.dbf, 0, length)
      assert {:error, [finding]} = Dbf.decode(bytes)
      assert finding.code == :dbf_header_truncated
    end

    too_many_records = replace(built.dbf, 4, <<10::unsigned-little-32>>)

    assert {:error, [finding]} = Dbf.decode(too_many_records, Limits.new!(records: 2))
    assert finding.code == :limit_records_exceeded

    truncated_records = binary_part(built.dbf, 0, byte_size(built.dbf) - 2)
    assert {:error, [finding]} = Dbf.decode(truncated_records)
    assert finding.code == :dbf_record_extent_invalid
  end

  test "field and finding limits are checked before unbounded work" do
    built = PairBuilder.build()

    assert {:error, [finding]} = Dbf.decode(built.dbf, Limits.new!(fields: 1))
    assert finding.code == :limit_fields_exceeded

    duplicate = replace(built.dbf, 64, binary_part(built.dbf, 32, 11))
    opaque_duplicate = replace(duplicate, 64 + 11, <<?X>>)

    assert {:error, [finding]} = Dbf.decode(opaque_duplicate, Limits.new!(findings: 1))
    assert finding.code == :limit_findings_exceeded
  end

  defp span(member, offset, length) do
    %VfpMcp.Source.Span{member: member, offset: offset, length: length}
  end

  defp finding_codes(findings), do: Enum.map(findings, & &1.code)

  defp replace(bytes, offset, replacement) do
    length = byte_size(replacement)
    <<prefix::binary-size(^offset), _old::binary-size(^length), suffix::binary>> = bytes
    prefix <> replacement <> suffix
  end
end
