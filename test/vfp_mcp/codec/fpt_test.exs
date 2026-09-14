defmodule VfpMcp.Codec.FptTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.{Dbf, Fpt}
  alias VfpMcp.Limits
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.memo_pointer
  # - vfp_mcp.codec.fpt_structure
  # - vfp_mcp.codec.memo_block
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.codec.parse_mixed_endian_pair
  # - vfp_mcp.codec.reject_invalid_memo

  test "normalizes and retains FPT header metadata for supported block sizes" do
    for {block_size, stored_size} <- [{1, 1}, {64, 64}, {512, 0}] do
      built =
        PairBuilder.build(
          block_size: block_size,
          stored_block_size: stored_size,
          fpt_header_opaque: <<0xAA, 0xBB>>
        )

      assert {:ok, fpt, []} = decode(built)
      assert fpt.header.next_free_block == built.layout.next_free_block
      assert fpt.header.stored_block_size == stored_size
      assert fpt.header.effective_block_size == block_size
      assert fpt.header.data_offset == built.layout.first_block * block_size
      assert fpt.header.next_free_offset == built.layout.next_free_block * block_size
      assert fpt.header.reserved_bytes.body |> binary_part(0, 2) == <<0xAA, 0xBB>>
      assert fpt.header.spans.next_free_block == span(:fpt, 0, 4)
      assert fpt.header.spans.stored_block_size == span(:fpt, 6, 2)
      assert fpt.header_bytes == binary_part(built.fpt, 0, 512)
    end
  end

  test "resolves little-endian DBF pointers into big-endian memo blocks" do
    built =
      PairBuilder.build(
        block_size: 64,
        records: [
          %{
            deleted?: false,
            values: %{
              "OBJNAME" => "frmMemo",
              "PROPERTIES" => {:memo, 1, <<"Caption = ", 0xE9>>}
            }
          }
        ]
      )

    assert {:ok, fpt, []} = decode(built)
    [expected] = built.layout.memo_blocks
    [memo_ref] = fpt.memo_refs
    block = Map.fetch!(fpt.blocks, expected.pointer)

    assert memo_ref.record_index == 0
    assert memo_ref.field == "PROPERTIES"
    assert memo_ref.pointer == expected.pointer
    assert memo_ref.pointer_bytes == <<expected.pointer::unsigned-little-32>>
    assert memo_ref.pointer_span.member == :dbf
    assert memo_ref.resolution == :resolved
    assert memo_ref.block_id == expected.pointer
    assert memo_ref.block_type == 1
    assert memo_ref.payload_bytes == expected.payload

    assert block.raw_header_bytes ==
             <<expected.block_type::unsigned-big-32,
               byte_size(expected.payload)::unsigned-big-32>>

    assert block.header_span == span(:fpt, expected.offset, 8)
    assert block.payload_span == span(:fpt, expected.offset + 8, byte_size(expected.payload))
    assert block.allocation_bytes == expected.bytes

    assert block.padding_bytes ==
             binary_part(
               expected.bytes,
               8 + byte_size(expected.payload),
               byte_size(expected.bytes) - 8 - byte_size(expected.payload)
             )
  end

  test "keeps empty and shared pointers distinct while sharing block identity" do
    built =
      PairBuilder.build(
        records: [
          record("first", {:memo, 1, "shared"}),
          record("second", {:memo, 1, "orphaned by test patch"}),
          record("empty", nil)
        ]
      )

    [first_block | _] = built.layout.memo_blocks

    second_pointer_offset =
      built.layout.records_offset + built.layout.record_length +
        built.layout.field_offsets["PROPERTIES"]

    patched_dbf =
      replace(
        built.dbf,
        second_pointer_offset,
        <<first_block.pointer::unsigned-little-32>>
      )

    assert {:ok, dbf, []} = Dbf.decode(patched_dbf)
    assert {:ok, fpt, []} = Fpt.decode(built.fpt, dbf)

    assert Enum.map(fpt.memo_refs, &{&1.record_index, &1.pointer, &1.resolution}) == [
             {0, first_block.pointer, :resolved},
             {1, first_block.pointer, :resolved},
             {2, 0, :empty}
           ]

    assert map_size(fpt.blocks) == 1
    assert Enum.at(fpt.memo_refs, 0).pointer_span != Enum.at(fpt.memo_refs, 1).pointer_span
  end

  test "invalid pointers retain provenance but expose no payload" do
    built = PairBuilder.build(block_size: 64)
    pointer_offset = built.layout.records_offset + built.layout.field_offsets["PROPERTIES"]

    cases = [
      {1, :fpt_pointer_before_data},
      {built.layout.next_free_block, :fpt_block_header_out_of_range}
    ]

    for {pointer, expected_code} <- cases do
      patched = replace(built.dbf, pointer_offset, <<pointer::unsigned-little-32>>)
      assert {:ok, dbf, []} = Dbf.decode(patched)
      assert {:ok, fpt, [finding]} = Fpt.decode(built.fpt, dbf)
      assert finding.code == expected_code
      [memo_ref] = fpt.memo_refs
      assert memo_ref.resolution == {:error, expected_code}
      assert memo_ref.pointer_bytes == <<pointer::unsigned-little-32>>
      assert memo_ref.payload_span == nil
      assert memo_ref.payload_bytes == nil
    end
  end

  test "rejects malformed allocation metadata and excessive payloads" do
    built = PairBuilder.build(block_size: 1)

    for length <- [0, 7, 511] do
      assert {:error, [finding]} = Fpt.decode(binary_part(built.fpt, 0, length), empty_dbf())
      assert finding.code == :fpt_header_truncated
    end

    assert {:error, [%{code: :fpt_next_free_before_data}]} =
             Fpt.decode(replace(built.fpt, 0, <<0::unsigned-big-32>>), empty_dbf())

    assert {:error, [%{code: :fpt_next_free_beyond_file}]} =
             Fpt.decode(replace(built.fpt, 0, <<999_999::unsigned-big-32>>), empty_dbf())

    assert {:error, [%{code: :limit_memo_blocks_exceeded}]} =
             Fpt.decode(built.fpt, empty_dbf(), Limits.new!(memo_blocks: 4))

    [memo] = built.layout.memo_blocks
    excessive = replace(built.fpt, memo.offset + 4, <<1_000::unsigned-big-32>>)
    assert {:ok, dbf, []} = Dbf.decode(built.dbf)

    assert {:error, [%{code: :limit_memo_payload_bytes_exceeded}]} =
             Fpt.decode(excessive, dbf, Limits.new!(memo_payload_bytes: 100))
  end

  test "rejects short and out-of-range block payloads without partial exposure" do
    built = PairBuilder.build(block_size: 1)
    pointer_offset = built.layout.records_offset + built.layout.field_offsets["PROPERTIES"]
    short_pointer = built.layout.next_free_block - 4
    short_dbf = replace(built.dbf, pointer_offset, <<short_pointer::unsigned-little-32>>)
    assert {:ok, dbf, []} = Dbf.decode(short_dbf)
    assert {:ok, fpt, [%{code: :fpt_block_header_out_of_range}]} = Fpt.decode(built.fpt, dbf)
    assert hd(fpt.memo_refs).payload_bytes == nil

    [memo] = built.layout.memo_blocks
    long_length = byte_size(built.fpt) - memo.offset
    long_fpt = replace(built.fpt, memo.offset + 4, <<long_length::unsigned-big-32>>)
    assert {:ok, original_dbf, []} = Dbf.decode(built.dbf)
    assert {:ok, fpt, [%{code: :fpt_payload_out_of_range}]} = Fpt.decode(long_fpt, original_dbf)
    assert hd(fpt.memo_refs).payload_bytes == nil
  end

  test "preserves unknown block types and rejects overlapping allocations" do
    unknown = PairBuilder.build(block_size: 64)
    [unknown_memo] = unknown.layout.memo_blocks
    unknown_fpt = replace(unknown.fpt, unknown_memo.offset, <<99::unsigned-big-32>>)
    assert {:ok, unknown_dbf, []} = Dbf.decode(unknown.dbf)
    assert {:ok, fpt, [%{code: :fpt_unknown_block_type}]} = Fpt.decode(unknown_fpt, unknown_dbf)
    assert Map.fetch!(fpt.blocks, unknown_memo.pointer).payload_bytes == unknown_memo.payload

    fake_header_payload =
      :binary.copy(<<0x41>>, 56) <>
        <<1::unsigned-big-32, 0::unsigned-big-32>> <>
        :binary.copy(<<0x42>>, 16)

    overlapping =
      PairBuilder.build(
        block_size: 64,
        records: [
          record("first", {:memo, 1, fake_header_payload}),
          record("second", {:memo, 1, "second"})
        ]
      )

    [first, _second] = overlapping.layout.memo_blocks

    second_pointer_offset =
      overlapping.layout.records_offset + overlapping.layout.record_length +
        overlapping.layout.field_offsets["PROPERTIES"]

    overlap_dbf =
      replace(overlapping.dbf, second_pointer_offset, <<first.pointer + 1::unsigned-little-32>>)

    assert {:ok, dbf, []} = Dbf.decode(overlap_dbf)
    assert {:ok, fpt, [%{code: :fpt_block_overlap}]} = Fpt.decode(overlapping.fpt, dbf)
    assert Enum.all?(fpt.memo_refs, &(&1.resolution == {:error, :fpt_block_overlap}))
    assert Enum.all?(fpt.memo_refs, &is_nil(&1.payload_bytes))
    refute Enum.any?(fpt.blocks, fn {_pointer, block} -> block.valid? end)
  end

  defp decode(built) do
    assert {:ok, dbf, []} = Dbf.decode(built.dbf)
    Fpt.decode(built.fpt, dbf)
  end

  defp empty_dbf do
    built =
      PairBuilder.build(
        fields: [%{name: "OBJNAME", type: :character, length: 8}],
        records: []
      )

    {:ok, dbf, []} = Dbf.decode(built.dbf)
    dbf
  end

  defp record(name, memo) do
    %{deleted?: false, values: %{"OBJNAME" => name, "PROPERTIES" => memo}}
  end

  defp span(member, offset, length) do
    %VfpMcp.Source.Span{member: member, offset: offset, length: length}
  end

  defp replace(bytes, offset, replacement) do
    length = byte_size(replacement)
    <<prefix::binary-size(^offset), _old::binary-size(^length), suffix::binary>> = bytes
    prefix <> replacement <> suffix
  end
end
