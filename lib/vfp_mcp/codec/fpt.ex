defmodule VfpMcp.Codec.Fpt.Header do
  @moduledoc "Physical FPT allocation metadata with raw bytes and spans."

  @enforce_keys [
    :next_free_block,
    :stored_block_size,
    :effective_block_size,
    :first_data_block,
    :data_offset,
    :next_free_offset,
    :reserved_bytes,
    :raw_bytes,
    :spans
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          next_free_block: non_neg_integer(),
          stored_block_size: non_neg_integer(),
          effective_block_size: pos_integer(),
          first_data_block: pos_integer(),
          data_offset: pos_integer(),
          next_free_offset: non_neg_integer(),
          reserved_bytes: %{prefix: binary(), body: binary()},
          raw_bytes: binary(),
          spans: %{required(atom()) => VfpMcp.Source.Span.t()}
        }
end

defmodule VfpMcp.Codec.Fpt.Block do
  @moduledoc "One resolved FPT memo block with exact allocation provenance."

  @enforce_keys [
    :pointer,
    :offset,
    :block_type,
    :payload_length,
    :raw_header_bytes,
    :payload_bytes,
    :padding_bytes,
    :allocation_bytes,
    :header_span,
    :payload_span,
    :allocation_span,
    :valid?
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          pointer: non_neg_integer(),
          offset: non_neg_integer(),
          block_type: non_neg_integer(),
          payload_length: non_neg_integer(),
          raw_header_bytes: binary(),
          payload_bytes: binary(),
          padding_bytes: binary(),
          allocation_bytes: binary(),
          header_span: VfpMcp.Source.Span.t(),
          payload_span: VfpMcp.Source.Span.t(),
          allocation_span: VfpMcp.Source.Span.t(),
          valid?: boolean()
        }
end

defmodule VfpMcp.Codec.Fpt do
  @moduledoc """
  Pure mixed-endian FPT decoder and DBF memo-pointer resolver.

  FPT integers are decoded as big-endian while the supplied DBF memo pointers
  are decoded as little-endian. Invalid pointers retain their DBF provenance but
  never expose guessed or partial payload bytes.
  """

  # specled covers:
  # - vfp_mcp.codec.memo_pointer
  # - vfp_mcp.codec.fpt_structure
  # - vfp_mcp.codec.memo_block
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Codec.Dbf
  alias VfpMcp.Codec.Fpt.{Block, Header}
  alias VfpMcp.{Finding, Limits}
  alias VfpMcp.Source.{MemoRef, Span}

  @header_size 512
  @block_header_size 8
  @known_block_types [0, 1]

  @enforce_keys [
    :bytes,
    :header,
    :blocks,
    :memo_refs,
    :header_bytes,
    :pre_data_bytes,
    :allocation_bytes,
    :trailing_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bytes: binary(),
          header: Header.t(),
          blocks: %{optional(non_neg_integer()) => Block.t()},
          memo_refs: [MemoRef.t()],
          header_bytes: binary(),
          pre_data_bytes: binary(),
          allocation_bytes: binary(),
          trailing_bytes: binary()
        }

  @type result :: {:ok, t(), [Finding.t()]} | {:error, [Finding.t()]}

  @spec decode(binary(), Dbf.t(), Limits.t()) :: result()
  def decode(bytes, dbf, limits \\ Limits.new!())

  def decode(bytes, %Dbf{} = dbf, %Limits{} = limits) when is_binary(bytes) do
    with {:ok, header, header_findings} <- decode_header(bytes, limits),
         {:ok, memo_refs, blocks, pointer_findings} <-
           resolve_pointers(bytes, dbf, header, limits, length(header_findings)),
         {:ok, memo_refs, blocks, overlap_findings} <-
           reject_overlaps(memo_refs, blocks, limits, length(header_findings ++ pointer_findings)) do
      findings = sort_findings(header_findings ++ pointer_findings ++ overlap_findings)
      trailing_length = byte_size(bytes) - header.next_free_offset

      {:ok,
       %__MODULE__{
         bytes: bytes,
         header: header,
         blocks: blocks,
         memo_refs: memo_refs,
         header_bytes: binary_part(bytes, 0, @header_size),
         pre_data_bytes: binary_part(bytes, @header_size, header.data_offset - @header_size),
         allocation_bytes:
           binary_part(bytes, header.data_offset, header.next_free_offset - header.data_offset),
         trailing_bytes: binary_part(bytes, header.next_free_offset, trailing_length)
       }, findings}
    end
  end

  def decode(_bytes, _dbf, _limits) do
    {:error,
     [Finding.fatal(:fpt_invalid_input, "FPT input, decoded DBF, and valid limits are required")]}
  end

  defp decode_header(bytes, _limits) when byte_size(bytes) < @header_size do
    fatal(:fpt_header_truncated, "FPT header is shorter than 512 bytes", byte_size(bytes), %{
      available: byte_size(bytes),
      required: @header_size
    })
  end

  defp decode_header(bytes, limits) do
    <<next_free_block::unsigned-big-32, reserved_prefix::binary-size(2),
      stored_block_size::unsigned-big-16, reserved_body::binary-size(504), _rest::binary>> = bytes

    block_size = if stored_block_size == 0, do: 512, else: stored_block_size
    first_data_block = ceil_div(@header_size, block_size)
    data_offset = first_data_block * block_size
    next_free_offset = next_free_block * block_size
    allocated_blocks = next_free_block - first_data_block

    cond do
      data_offset > byte_size(bytes) ->
        fatal(:fpt_data_offset_invalid, "FPT block size places data beyond the member", 6, %{
          block_size: block_size,
          data_offset: data_offset,
          member_bytes: byte_size(bytes)
        })

      next_free_block < first_data_block ->
        fatal(:fpt_next_free_before_data, "FPT next-free block precedes memo data", 0, %{
          next_free_block: next_free_block,
          first_data_block: first_data_block
        })

      next_free_offset > byte_size(bytes) ->
        fatal(:fpt_next_free_beyond_file, "FPT next-free location exceeds the member", 0, %{
          next_free_offset: next_free_offset,
          member_bytes: byte_size(bytes)
        })

      allocated_blocks > limits.memo_blocks ->
        {:error,
         [
           Finding.fatal(:limit_memo_blocks_exceeded, "memo_blocks limit exceeded",
             location: %{member: :fpt, offset: 0},
             evidence: %{actual: allocated_blocks, maximum: limits.memo_blocks}
           )
         ]}

      true ->
        trailing_length = byte_size(bytes) - next_free_offset

        findings =
          if trailing_length > 0 and rem(trailing_length, block_size) != 0 do
            [
              Finding.new(
                :fpt_unaligned_trailing_bytes,
                :warning,
                :preserved,
                "bytes after the FPT next-free location are not block aligned",
                location: %{member: :fpt, offset: next_free_offset},
                evidence: %{bytes: trailing_length, block_size: block_size}
              )
            ]
          else
            []
          end

        {:ok,
         %Header{
           next_free_block: next_free_block,
           stored_block_size: stored_block_size,
           effective_block_size: block_size,
           first_data_block: first_data_block,
           data_offset: data_offset,
           next_free_offset: next_free_offset,
           reserved_bytes: %{prefix: reserved_prefix, body: reserved_body},
           raw_bytes: binary_part(bytes, 0, @header_size),
           spans: %{
             next_free_block: Span.new(:fpt, 0, 4),
             reserved_prefix: Span.new(:fpt, 4, 2),
             stored_block_size: Span.new(:fpt, 6, 2),
             reserved_body: Span.new(:fpt, 8, 504)
           }
         }, findings}
    end
  end

  defp resolve_pointers(bytes, dbf, header, limits, existing_findings) do
    pointer_values =
      for record <- dbf.records,
          value <- record.values,
          value.type == :memo do
        {record.index, value}
      end

    pointer_values
    |> Enum.reduce_while({[], %{}, [], existing_findings}, fn {record_index, value}, state ->
      {refs, blocks, findings, finding_count} = state

      case resolve_pointer(bytes, header, record_index, value, blocks, limits) do
        {:error, [finding]} ->
          {:halt, {:error, [finding]}}

        {:ok, memo_ref, block, new_findings} ->
          if finding_count + length(new_findings) > limits.findings do
            {:halt,
             limit_findings_error(limits, finding_count + length(new_findings), value.span.offset)}
          else
            next_blocks = if block, do: Map.put_new(blocks, block.pointer, block), else: blocks

            {:cont,
             {
               [memo_ref | refs],
               next_blocks,
               Enum.reverse(new_findings) ++ findings,
               finding_count + length(new_findings)
             }}
          end
      end
    end)
    |> case do
      {:error, _findings} = error ->
        error

      {refs, blocks, findings, _count} ->
        {:ok, Enum.reverse(refs), blocks, Enum.reverse(findings)}
    end
  end

  defp resolve_pointer(_bytes, _header, record_index, value, _blocks, _limits)
       when byte_size(value.raw_bytes) != 4 do
    finding =
      Finding.new(
        :dbf_memo_pointer_width_invalid,
        :error,
        :mutation_blocked,
        "DBF memo pointer is not four bytes",
        location: %{member: :dbf, offset: value.span.offset},
        evidence: %{
          record: record_index,
          field: value.field_name,
          bytes: byte_size(value.raw_bytes)
        }
      )

    {:ok, memo_ref(record_index, value, nil, {:error, :dbf_memo_pointer_width_invalid}), nil,
     [finding]}
  end

  defp resolve_pointer(bytes, header, record_index, value, blocks, limits) do
    <<pointer::unsigned-little-32>> = value.raw_bytes

    cond do
      pointer == 0 ->
        {:ok, memo_ref(record_index, value, 0, :empty), nil, []}

      Map.has_key?(blocks, pointer) ->
        block = Map.fetch!(blocks, pointer)
        {:ok, memo_ref(record_index, value, pointer, :resolved, block), block, []}

      map_size(blocks) >= limits.memo_blocks ->
        {:error,
         [
           Finding.fatal(:limit_memo_blocks_exceeded, "memo_blocks limit exceeded",
             location: %{member: :dbf, offset: value.span.offset},
             evidence: %{actual: map_size(blocks) + 1, maximum: limits.memo_blocks}
           )
         ]}

      true ->
        resolve_new_block(bytes, header, record_index, value, pointer, limits)
    end
  end

  defp resolve_new_block(bytes, header, record_index, value, pointer, limits) do
    offset = pointer * header.effective_block_size
    boundary = min(header.next_free_offset, byte_size(bytes))

    cond do
      offset < header.data_offset ->
        invalid_pointer(
          record_index,
          value,
          pointer,
          :fpt_pointer_before_data,
          "memo pointer resolves before FPT data",
          %{calculated_offset: offset, data_offset: header.data_offset}
        )

      offset + @block_header_size > boundary ->
        invalid_pointer(
          record_index,
          value,
          pointer,
          :fpt_block_header_out_of_range,
          "memo block header is outside allocated FPT bytes",
          %{calculated_offset: offset, allocation_end: boundary}
        )

      true ->
        raw_header = binary_part(bytes, offset, @block_header_size)
        <<block_type::unsigned-big-32, payload_length::unsigned-big-32>> = raw_header

        cond do
          payload_length > limits.memo_payload_bytes ->
            {:error,
             [
               Finding.fatal(
                 :limit_memo_payload_bytes_exceeded,
                 "memo_payload_bytes limit exceeded",
                 location: %{member: :fpt, offset: offset + 4},
                 evidence: %{actual: payload_length, maximum: limits.memo_payload_bytes}
               )
             ]}

          offset + @block_header_size + payload_length > boundary ->
            invalid_pointer(
              record_index,
              value,
              pointer,
              :fpt_payload_out_of_range,
              "memo payload extends outside allocated FPT bytes",
              %{payload_length: payload_length, allocation_end: boundary}
            )

          true ->
            allocation_length =
              ceil_div(@block_header_size + payload_length, header.effective_block_size) *
                header.effective_block_size

            allocation_end = offset + allocation_length

            if allocation_end > boundary do
              invalid_pointer(
                record_index,
                value,
                pointer,
                :fpt_block_allocation_out_of_range,
                "memo block allocation extends outside allocated FPT bytes",
                %{allocation_end: allocation_end, fpt_allocation_end: boundary}
              )
            else
              payload_offset = offset + @block_header_size
              payload = binary_part(bytes, payload_offset, payload_length)
              padding_length = allocation_length - @block_header_size - payload_length
              padding = binary_part(bytes, payload_offset + payload_length, padding_length)
              allocation = binary_part(bytes, offset, allocation_length)

              block = %Block{
                pointer: pointer,
                offset: offset,
                block_type: block_type,
                payload_length: payload_length,
                raw_header_bytes: raw_header,
                payload_bytes: payload,
                padding_bytes: padding,
                allocation_bytes: allocation,
                header_span: Span.new(:fpt, offset, @block_header_size),
                payload_span: Span.new(:fpt, payload_offset, payload_length),
                allocation_span: Span.new(:fpt, offset, allocation_length),
                valid?: true
              }

              findings =
                if block_type in @known_block_types do
                  []
                else
                  [
                    Finding.new(
                      :fpt_unknown_block_type,
                      :warning,
                      :preserved,
                      "unknown FPT block type is retained as opaque bytes",
                      location: %{member: :fpt, offset: offset},
                      evidence: %{block_type: block_type, pointer: pointer}
                    )
                  ]
                end

              {:ok, memo_ref(record_index, value, pointer, :resolved, block), block, findings}
            end
        end
    end
  end

  defp invalid_pointer(record_index, value, pointer, code, message, evidence) do
    finding =
      Finding.new(code, :error, :mutation_blocked, message,
        location: %{member: :dbf, offset: value.span.offset},
        evidence:
          Map.merge(evidence, %{record: record_index, field: value.field_name, pointer: pointer})
      )

    {:ok, memo_ref(record_index, value, pointer, {:error, code}), nil, [finding]}
  end

  defp reject_overlaps(memo_refs, blocks, limits, existing_findings) do
    overlaps =
      blocks
      |> Map.values()
      |> Enum.sort_by(& &1.offset)
      |> overlapping_pairs()

    if existing_findings + length(overlaps) > limits.findings do
      limit_findings_error(limits, existing_findings + length(overlaps), 0)
    else
      invalid_pointers =
        overlaps
        |> Enum.flat_map(fn [left, right] -> [left.pointer, right.pointer] end)
        |> MapSet.new()

      findings =
        Enum.map(overlaps, fn [left, right] ->
          Finding.new(
            :fpt_block_overlap,
            :error,
            :mutation_blocked,
            "resolved FPT memo allocations overlap",
            location: %{member: :fpt, offset: right.offset},
            evidence: %{left_pointer: left.pointer, right_pointer: right.pointer}
          )
        end)

      next_blocks =
        Map.new(blocks, fn {pointer, block} ->
          {pointer,
           if(MapSet.member?(invalid_pointers, pointer),
             do: %{block | valid?: false},
             else: block
           )}
        end)

      next_refs =
        Enum.map(memo_refs, fn memo_ref ->
          if MapSet.member?(invalid_pointers, memo_ref.pointer) do
            %{
              memo_ref
              | resolution: {:error, :fpt_block_overlap},
                payload_span: nil,
                payload_bytes: nil
            }
          else
            memo_ref
          end
        end)

      {:ok, next_refs, next_blocks, findings}
    end
  end

  defp overlapping_pairs(blocks) do
    blocks
    |> Enum.reduce({[], nil, 0}, fn block, {overlaps, active, active_end} ->
      block_end = block.allocation_span.offset + block.allocation_span.length

      cond do
        is_nil(active) ->
          {overlaps, block, block_end}

        block.offset < active_end and block_end > active_end ->
          {[[active, block] | overlaps], block, block_end}

        block.offset < active_end ->
          {[[active, block] | overlaps], active, active_end}

        true ->
          {overlaps, block, block_end}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp memo_ref(record_index, value, pointer, resolution, block \\ nil) do
    %MemoRef{
      record_index: record_index,
      field: value.field_name,
      pointer: pointer,
      pointer_bytes: value.raw_bytes,
      pointer_span: value.span,
      resolution: resolution,
      block_id: block && block.pointer,
      block_type: block && block.block_type,
      block_span: block && block.header_span,
      payload_span: block && block.payload_span,
      payload_bytes: block && block.payload_bytes,
      allocation_span: block && block.allocation_span,
      raw_block_header_bytes: block && block.raw_header_bytes,
      padding_bytes: block && block.padding_bytes
    }
  end

  defp limit_findings_error(limits, actual, offset) do
    {:error,
     [
       Finding.fatal(:limit_findings_exceeded, "findings limit exceeded",
         location: %{member: :fpt, offset: offset},
         evidence: %{actual: actual, maximum: limits.findings}
       )
     ]}
  end

  defp fatal(code, message, offset, evidence) do
    {:error,
     [
       Finding.fatal(code, message,
         location: %{member: :fpt, offset: offset},
         evidence: evidence
       )
     ]}
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp sort_findings(findings) do
    Enum.sort_by(findings, fn finding ->
      {Atom.to_string(finding.code), inspect(finding.location), inspect(finding.evidence)}
    end)
  end
end
