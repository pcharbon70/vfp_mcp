defmodule VfpMcp.Integration.Phase2PhysicalCodecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias VfpMcp.Codec
  alias VfpMcp.Codec.PhysicalSummary
  alias VfpMcp.Limits
  alias VfpMcp.Source.PairSnapshot
  alias VfpMcp.TestSupport.PairBuilder

  # specled covers:
  # - vfp_mcp.codec.dbf_structure
  # - vfp_mcp.codec.memo_pointer
  # - vfp_mcp.codec.fpt_structure
  # - vfp_mcp.codec.memo_block
  # - vfp_mcp.codec.lossless_encoding
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.codec.parse_mixed_endian_pair
  # - vfp_mcp.codec.reject_invalid_memo
  # - vfp_mcp.acceptance.codec_evidence
  # - vfp_mcp.acceptance.run_phase2_codec_suite
  # - vfp_mcp.protocol.sdk_boundary

  test "golden vectors prove mixed endianness and exact source spans" do
    for {kind, block_size, stored_size, deleted?, block_type, code_page} <- [
          {:scx, 1, 1, false, 1, 0x03},
          {:vcx, 64, 64, true, 7, 0x57},
          {:scx, 512, 0, false, 0, 0x03}
        ] do
      built =
        PairBuilder.build(
          kind: kind,
          block_size: block_size,
          stored_block_size: stored_size,
          code_page: code_page,
          records: [record(deleted?, {:memo, block_type, <<1, 2, 3, 4>>})]
        )

      assert {:ok, document} = Codec.parse_pair(built.snapshot)
      dbf = document.physical.dbf
      fpt = document.physical.fpt
      [record] = dbf.records
      [memo_ref] = fpt.memo_refs
      block = Map.fetch!(fpt.blocks, memo_ref.pointer)

      assert dbf.header.record_count == 1
      assert dbf.header.spans.record_count.offset == 4
      assert dbf.header.spans.record_count.length == 4
      assert record.deleted? == deleted?
      assert record.span.offset == built.layout.records_offset
      assert memo_ref.pointer_bytes == <<memo_ref.pointer::unsigned-little-32>>

      assert memo_ref.pointer_span.offset ==
               built.layout.records_offset + built.layout.field_offsets["PROPERTIES"]

      assert fpt.header.stored_block_size == stored_size
      assert fpt.header.effective_block_size == block_size

      assert binary_part(built.fpt, 0, 4) ==
               <<fpt.header.next_free_block::unsigned-big-32>>

      assert binary_part(built.fpt, 6, 2) == <<stored_size::unsigned-big-16>>
      assert block.offset == memo_ref.pointer * block_size

      assert block.raw_header_bytes ==
               <<block_type::unsigned-big-32, 4::unsigned-big-32>>

      assert block.payload_span.offset == block.offset + 8
      assert block.payload_bytes == <<1, 2, 3, 4>>
    end
  end

  property "bounded valid pairs parse deterministically and retain non-overlapping spans" do
    check all(
            kind <- member_of([:scx, :vcx]),
            block_size <- member_of([1, 64, 512]),
            zero_means_512? <- boolean(),
            deleted? <- boolean(),
            block_type <- member_of([0, 1, 7]),
            code_page <- member_of([0x03, 0x57]),
            object_bytes <- binary(max_length: 10),
            payload <- binary(max_length: 128),
            max_runs: 75
          ) do
      stored_size = if block_size == 512 and zero_means_512?, do: 0, else: block_size

      built =
        PairBuilder.build(
          kind: kind,
          block_size: block_size,
          stored_block_size: stored_size,
          code_page: code_page,
          records: [
            %{
              deleted?: deleted?,
              values: %{"OBJNAME" => object_bytes, "PROPERTIES" => {:memo, block_type, payload}}
            }
          ]
        )

      assert {:ok, first} = Codec.parse_pair(built.snapshot)
      assert {:ok, second} = Codec.parse_pair(built.snapshot)
      assert first == second
      assert PhysicalSummary.encode(first) == PhysicalSummary.encode(second)
      assert first.physical.raw == %{dbf: built.dbf, fpt: built.fpt}

      [memo_ref] = first.physical.fpt.memo_refs
      assert memo_ref.resolution == :resolved
      assert memo_ref.payload_bytes == payload
      assert spans_non_overlapping?(hd(first.records).values)
      assert allocations_non_overlapping?(first.physical.fpt.blocks)
    end
  end

  test "DBF adversarial boundaries return deterministic structured results" do
    built = PairBuilder.build()

    cases = [
      {binary_part(built.dbf, 0, 31), built.fpt, Limits.new!(), :dbf_header_truncated},
      {replace(built.dbf, built.layout.header_length - 1, <<0>>), built.fpt, Limits.new!(),
       :dbf_descriptor_truncated},
      {replace(built.dbf, 10, <<6::unsigned-little-16>>), built.fpt, Limits.new!(),
       :dbf_schema_width_exceeded},
      {replace(built.dbf, 4, <<0xFFFF_FFFF::unsigned-little-32>>), built.fpt, Limits.new!(),
       :limit_records_exceeded},
      {binary_part(built.dbf, 0, byte_size(built.dbf) - 2), built.fpt, Limits.new!(),
       :dbf_record_extent_invalid}
    ]

    for {dbf_bytes, fpt_bytes, limits, expected_code} <- cases do
      snapshot = snapshot(dbf_bytes, fpt_bytes)
      assert first = Codec.parse_pair(snapshot, limits: limits)
      assert first == Codec.parse_pair(snapshot, limits: limits)
      assert {:error, findings} = first
      assert Enum.map(findings, & &1.code) == [expected_code]
    end

    invalid_marker = replace(built.dbf, built.layout.records_offset, <<0x7F>>)
    assert {:ok, document} = Codec.parse_pair(snapshot(invalid_marker, built.fpt))
    assert Enum.any?(document.findings, &(&1.code == :dbf_invalid_record_marker))

    assert hd(document.records).raw_bytes ==
             binary_part(invalid_marker, built.layout.records_offset, built.layout.record_length)
  end

  test "FPT adversarial boundaries never expose an invalid memo payload" do
    built = PairBuilder.build(block_size: 64)
    [memo] = built.layout.memo_blocks
    pointer_offset = built.layout.records_offset + built.layout.field_offsets["PROPERTIES"]

    cases = [
      {built.dbf, binary_part(built.fpt, 0, 511), Limits.new!(), :fpt_header_truncated},
      {built.dbf, replace(built.fpt, 6, <<4096::unsigned-big-16>>), Limits.new!(),
       :fpt_data_offset_invalid},
      {replace(built.dbf, pointer_offset, <<1::unsigned-little-32>>), built.fpt, Limits.new!(),
       :fpt_pointer_before_data},
      {replace(
         built.dbf,
         pointer_offset,
         <<built.layout.next_free_block::unsigned-little-32>>
       ), built.fpt, Limits.new!(), :fpt_block_header_out_of_range},
      {built.dbf, replace(built.fpt, memo.offset + 4, <<1_000::unsigned-big-32>>),
       Limits.new!(memo_payload_bytes: 100), :limit_memo_payload_bytes_exceeded}
    ]

    for {dbf_bytes, fpt_bytes, limits, expected_code} <- cases do
      result = Codec.parse_pair(snapshot(dbf_bytes, fpt_bytes), limits: limits)
      assert result == Codec.parse_pair(snapshot(dbf_bytes, fpt_bytes), limits: limits)

      case result do
        {:error, findings} ->
          assert Enum.map(findings, & &1.code) == [expected_code]

        {:ok, document} ->
          assert Enum.any?(document.findings, &(&1.code == expected_code))
          assert Enum.all?(document.physical.fpt.memo_refs, &is_nil(&1.payload_bytes))
      end
    end
  end

  property "arbitrary bounded member bytes never raise or return an invalid shape" do
    check all(
            dbf_bytes <- binary(max_length: 1024),
            fpt_bytes <- binary(max_length: 1024),
            kind <- member_of([:scx, :vcx]),
            max_runs: 100
          ) do
      {:ok, pair} = PairSnapshot.new(kind, "phase2-adversarial", dbf_bytes, fpt_bytes)
      result = Codec.parse_pair(pair, limits: Limits.new!(member_bytes: 2048, records: 32))

      assert match?({:ok, %VfpMcp.Document{}}, result) or
               match?({:error, [%VfpMcp.Finding{} | _]}, result)
    end
  end

  test "all opaque DBF and FPT regions are recoverable at original offsets" do
    built =
      PairBuilder.build(
        block_size: 64,
        code_page: 0x03,
        dbf_header_opaque: <<0xA1, 0xA2, 0xA3>>,
        fpt_header_opaque: <<0xB1, 0xB2, 0xB3>>,
        dbf_trailing: <<0x1A, 0xC1, 0xC2>>,
        fpt_trailing: <<0xD1, 0xD2>>,
        records: [record(true, {:memo, 99, <<0xD0, 0xCF, 0x11, 0xE0, 0, 1, 2, 3>>})]
      )

    descriptor_reserved_offset = 32 + 19
    [memo] = built.layout.memo_blocks
    padding_offset = memo.offset + 8 + byte_size(memo.payload)

    dbf_bytes = replace(built.dbf, descriptor_reserved_offset, <<0xE1, 0xE2, 0xE3>>)
    fpt_bytes = replace(built.fpt, padding_offset, <<0xF1, 0xF2, 0xF3>>)
    pair = snapshot(dbf_bytes, fpt_bytes)

    assert {:ok, document} = Codec.parse_pair(pair)
    dbf = document.physical.dbf
    fpt = document.physical.fpt
    block = fpt.blocks[memo.pointer]

    assert dbf.header_bytes <> dbf.records_bytes <> dbf.trailing_bytes == dbf_bytes

    assert fpt.header_bytes <>
             fpt.pre_data_bytes <>
             fpt.allocation_bytes <>
             fpt.trailing_bytes == fpt_bytes

    assert binary_part(dbf_bytes, hd(dbf.fields).descriptor_span.offset, 32) ==
             hd(dbf.fields).raw_bytes

    assert hd(dbf.records).deleted?

    assert binary_part(fpt_bytes, block.allocation_span.offset, block.allocation_span.length) ==
             block.allocation_bytes

    assert block.block_type == 99
    assert block.payload_bytes == memo.payload
    assert binary_part(block.padding_bytes, 0, 3) == <<0xF1, 0xF2, 0xF3>>
    assert Enum.any?(document.findings, &(&1.code == :fpt_unknown_block_type))
  end

  test "parse values, finding order, spans, and summaries ignore process order" do
    built = PairBuilder.build(code_page: 0x00, dbf_trailing: <<0x1A, 0xEE>>)

    results =
      1..20
      |> Enum.map(fn _index -> Task.async(fn -> Codec.parse_pair(built.snapshot) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.uniq(results) |> length() == 1
    [{:ok, document}] = Enum.uniq(results)
    summaries = Enum.map(1..20, fn _index -> PhysicalSummary.encode(document) end)
    assert Enum.uniq(summaries) == [hd(summaries)]

    assert document.findings
           |> Enum.map(& &1.code)
           |> Enum.filter(&(&1 in [:codec_unsupported_code_page, :dbf_trailing_bytes_preserved])) ==
             [:codec_unsupported_code_page, :dbf_trailing_bytes_preserved]
  end

  test "the public codec ignores identity paths and returns SDK-neutral data" do
    built = PairBuilder.build()

    {:ok, path_snapshot} =
      PairSnapshot.new(:scx, "phase2-pure", built.dbf, built.fpt,
        declared_vfp_version: 9,
        dbf_path: "Z:/not-mounted/original-application/never-open.scx",
        fpt_path: "Z:/not-mounted/original-application/never-open.sct"
      )

    assert {:ok, document} = Codec.parse_pair(path_snapshot)
    assert document.physical.raw == %{dbf: built.dbf, fpt: built.fpt}
    refute inspect(document) =~ "ExMCP"
    refute contains_effect_handle?(document)
  end

  defp record(deleted?, memo) do
    %{
      deleted?: deleted?,
      values: %{"OBJNAME" => "phase2", "PROPERTIES" => memo}
    }
  end

  defp snapshot(dbf_bytes, fpt_bytes) do
    {:ok, snapshot} =
      PairSnapshot.new(:scx, "phase2-integration", dbf_bytes, fpt_bytes, declared_vfp_version: 9)

    snapshot
  end

  defp spans_non_overlapping?(values) do
    values
    |> Enum.map(& &1.span)
    |> Enum.sort_by(& &1.offset)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left.offset + left.length <= right.offset end)
  end

  defp allocations_non_overlapping?(blocks) do
    blocks
    |> Map.values()
    |> Enum.map(& &1.allocation_span)
    |> Enum.sort_by(& &1.offset)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left.offset + left.length <= right.offset end)
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

  defp replace(bytes, offset, replacement) do
    length = byte_size(replacement)
    <<prefix::binary-size(^offset), _old::binary-size(^length), suffix::binary>> = bytes
    prefix <> replacement <> suffix
  end
end
