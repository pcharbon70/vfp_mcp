defmodule VfpMcp.TestSupport.PairBuilderTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.acceptance.deterministic_test_vectors

  test "builder exposes exact endian values, offsets, pointers, and opaque bytes" do
    built =
      PairBuilder.build(
        block_size: 64,
        code_page: 0x03,
        dbf_header_opaque: <<0xAA, 0xBB>>,
        fpt_header_opaque: <<0xCC, 0xDD>>,
        dbf_trailing: <<0x1A, 0xEE>>,
        fpt_trailing: <<0xFF>>
      )

    assert <<0x30, 0, 0, 0, 1::unsigned-little-32, header_length::unsigned-little-16,
             record_length::unsigned-little-16, 0xAA, 0xBB, _::binary>> = built.dbf

    assert header_length == built.layout.header_length
    assert record_length == built.layout.record_length
    assert :binary.at(built.dbf, 29) == 0x03
    assert :binary.part(built.dbf, byte_size(built.dbf) - 2, 2) == <<0x1A, 0xEE>>

    [memo] = built.layout.memo_blocks
    pointer_offset = built.layout.records_offset + built.layout.field_offsets["PROPERTIES"]
    memo_pointer = memo.pointer
    next_free_block = built.layout.next_free_block
    block_type = memo.block_type
    payload = memo.payload
    payload_size = byte_size(payload)

    assert <<memo_pointer::unsigned-little-32>> ==
             :binary.part(built.dbf, pointer_offset, 4)

    assert <<^next_free_block::unsigned-big-32, 0, 0, 64::unsigned-big-16, 0xCC, 0xDD, _::binary>> =
             built.fpt

    assert memo.offset == memo.pointer * 64

    assert <<^block_type::unsigned-big-32, ^payload_size::unsigned-big-32,
             ^payload::binary-size(^payload_size), _::binary>> =
             :binary.part(built.fpt, memo.offset, byte_size(memo.bytes))

    assert :binary.last(built.fpt) == 0xFF
  end

  test "builder controls deletion markers, schemas, and zero-as-512 block size" do
    built =
      PairBuilder.build(
        kind: :vcx,
        block_size: 512,
        stored_block_size: 0,
        fields: [
          %{name: "OBJNAME", type: :character, length: 8},
          %{name: "METHODS", type: :memo, length: 4}
        ],
        records: [
          %{
            deleted?: true,
            values: %{"OBJNAME" => "Button", "METHODS" => {:memo, 7, <<0, 1, 2>>}}
          }
        ]
      )

    assert built.snapshot.identity.kind == :vcx
    assert :binary.at(built.dbf, built.layout.records_offset) == 0x2A
    assert :binary.part(built.fpt, 6, 2) == <<0, 0>>
    assert built.layout.block_size == 512
    assert hd(built.layout.memo_blocks).block_type == 7
    assert hd(built.layout.memo_blocks).payload == <<0, 1, 2>>
  end

  test "malformed vectors are deterministic and retain valid snapshot identity" do
    built = PairBuilder.build()
    first = PairBuilder.malformed(built, {:truncate, :fpt, 13})
    second = PairBuilder.malformed(built, {:truncate, :fpt, 13})

    assert first == second
    assert byte_size(first.fpt) == byte_size(built.fpt) - 13
    assert :ok = VfpMcp.Source.PairSnapshot.validate(first.snapshot)
  end

  property "generated pairs are deterministic across block sizes and payloads" do
    check all(
            block_size <- member_of([1, 64, 512]),
            code_page <- integer(0..255),
            payload <- binary(max_length: 128),
            max_runs: 30
          ) do
      stored_block_size = if block_size == 512 and rem(code_page, 2) == 0, do: 0, else: block_size

      opts = [
        block_size: block_size,
        stored_block_size: stored_block_size,
        code_page: code_page,
        records: [
          %{
            deleted?: false,
            values: %{"OBJNAME" => "Generated", "PROPERTIES" => {:memo, 1, payload}}
          }
        ]
      ]

      first = PairBuilder.build(opts)
      second = PairBuilder.build(opts)

      assert first == second
      assert :ok = VfpMcp.Source.PairSnapshot.validate(first.snapshot)

      [memo] = first.layout.memo_blocks
      assert memo.offset == memo.pointer * block_size
      assert :binary.part(first.fpt, memo.offset + 8, byte_size(payload)) == payload
    end
  end
end
