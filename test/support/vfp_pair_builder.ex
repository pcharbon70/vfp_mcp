defmodule VfpMcp.TestSupport.PairBuilder do
  @moduledoc """
  Deterministic DBF/FPT byte builder for tests.

  It supports declarative schemas, deletion markers, memo pointers, endian
  headers, block-size variants, and caller-supplied opaque regions. It never
  reads or writes a file.
  """

  @default_fields [
    %{name: "OBJNAME", type: :character, length: 12},
    %{name: "PROPERTIES", type: :memo, length: 4}
  ]

  @default_records [
    %{
      deleted?: false,
      values: %{
        "OBJNAME" => "frmBasic",
        "PROPERTIES" => {:memo, 1, "Caption = \"Synthetic\""}
      }
    }
  ]

  @spec build(keyword()) :: map()
  def build(opts \\ []) do
    kind = Keyword.get(opts, :kind, :scx)
    source_id = Keyword.get(opts, :source_id, "generated")
    version = Keyword.get(opts, :declared_vfp_version, 9)
    fields = Keyword.get(opts, :fields, @default_fields)
    records = Keyword.get(opts, :records, @default_records)
    block_size = Keyword.get(opts, :block_size, 64)
    stored_block_size = Keyword.get(opts, :stored_block_size, block_size)
    code_page = Keyword.get(opts, :code_page, 0x03)

    validate_options!(kind, fields, block_size, stored_block_size, code_page)

    first_block = ceil_div(512, block_size)

    {prepared_records, memo_blocks, next_free_block} =
      prepare_records(records, fields, block_size, first_block)

    {dbf_bytes, dbf_layout} =
      build_dbf(prepared_records, fields, code_page,
        header_opaque: Keyword.get(opts, :dbf_header_opaque, <<>>),
        trailing: Keyword.get(opts, :dbf_trailing, <<0x1A>>)
      )

    fpt_bytes =
      build_fpt(memo_blocks, next_free_block, block_size, stored_block_size,
        header_opaque: Keyword.get(opts, :fpt_header_opaque, <<>>),
        trailing: Keyword.get(opts, :fpt_trailing, <<>>)
      )

    {:ok, snapshot} =
      VfpMcp.Source.PairSnapshot.new(kind, source_id, dbf_bytes, fpt_bytes,
        declared_vfp_version: version
      )

    %{
      snapshot: snapshot,
      dbf: dbf_bytes,
      fpt: fpt_bytes,
      layout:
        Map.merge(dbf_layout, %{
          block_size: block_size,
          stored_block_size: stored_block_size,
          first_block: first_block,
          next_free_block: next_free_block,
          memo_blocks: memo_blocks
        })
    }
  end

  @spec malformed(map(), {:truncate, :dbf | :fpt, non_neg_integer()}) :: map()
  def malformed(%{snapshot: snapshot} = built, {:truncate, member, remove_bytes})
      when member in [:dbf, :fpt] and is_integer(remove_bytes) and remove_bytes >= 0 do
    dbf = if member == :dbf, do: truncate(built.dbf, remove_bytes), else: built.dbf
    fpt = if member == :fpt, do: truncate(built.fpt, remove_bytes), else: built.fpt

    {:ok, malformed_snapshot} =
      VfpMcp.Source.PairSnapshot.new(
        snapshot.identity.kind,
        snapshot.identity.source_id,
        dbf,
        fpt,
        declared_vfp_version: snapshot.identity.declared_vfp_version
      )

    %{built | dbf: dbf, fpt: fpt, snapshot: malformed_snapshot}
  end

  defp validate_options!(kind, fields, block_size, stored_block_size, code_page) do
    unless kind in [:scx, :vcx], do: raise(ArgumentError, "kind must be :scx or :vcx")
    unless is_list(fields) and fields != [], do: raise(ArgumentError, "fields are required")

    unless is_integer(block_size) and block_size > 0,
      do: raise(ArgumentError, "invalid block size")

    unless stored_block_size == block_size or (stored_block_size == 0 and block_size == 512) do
      raise ArgumentError, "stored block size must match effective block size or use zero for 512"
    end

    unless is_integer(code_page) and code_page in 0..255,
      do: raise(ArgumentError, "code page must fit one byte")

    Enum.each(fields, fn field ->
      unless is_binary(field.name) and byte_size(field.name) in 1..10,
        do: raise(ArgumentError, "field names must contain 1 to 10 bytes")

      unless field.type in [:character, :memo],
        do: raise(ArgumentError, "only character and memo fields are supported")

      unless is_integer(field.length) and field.length in 1..255,
        do: raise(ArgumentError, "field length must fit one byte")

      if field.type == :memo and field.length != 4,
        do: raise(ArgumentError, "memo fields must be four bytes")
    end)
  end

  defp prepare_records(records, fields, block_size, first_block) do
    {records, {blocks, next_block}} =
      Enum.map_reduce(records, {[], first_block}, fn record, {blocks, next_block} ->
        {values, {blocks, next_block}} =
          Enum.map_reduce(fields, {blocks, next_block}, fn field, {field_blocks, block} ->
            value = Map.get(record.values, field.name, default_value(field.type))

            case {field.type, value} do
              {:memo, nil} ->
                {0, {field_blocks, block}}

              {:memo, {:memo, block_type, payload}} when is_binary(payload) ->
                allocated_blocks = ceil_div(8 + byte_size(payload), block_size)
                allocation_size = allocated_blocks * block_size

                bytes =
                  pad(
                    <<block_type::unsigned-big-32, byte_size(payload)::unsigned-big-32,
                      payload::binary>>,
                    allocation_size,
                    0
                  )

                memo = %{
                  pointer: block,
                  offset: block * block_size,
                  block_type: block_type,
                  payload: payload,
                  bytes: bytes,
                  allocated_blocks: allocated_blocks
                }

                {block, {field_blocks ++ [memo], block + allocated_blocks}}

              {:character, value} when is_binary(value) ->
                {value, {field_blocks, block}}

              _other ->
                raise ArgumentError, "record value does not match field type"
            end
          end)

        {%{deleted?: Map.get(record, :deleted?, false), values: values}, {blocks, next_block}}
      end)

    {records, blocks, next_block}
  end

  defp build_dbf(records, fields, code_page, opts) do
    record_count = length(records)
    header_length = 32 + 32 * length(fields) + 1
    record_length = 1 + Enum.sum(Enum.map(fields, & &1.length))
    header_opaque = pad(Keyword.fetch!(opts, :header_opaque), 17, 0)

    header =
      <<0x30, 0, 0, 0, record_count::unsigned-little-32, header_length::unsigned-little-16,
        record_length::unsigned-little-16, header_opaque::binary-size(17), code_page, 0, 0>>

    {descriptors, field_offsets, _next_offset} =
      Enum.reduce(fields, {[], %{}, 1}, fn field, {descriptors, offsets, offset} ->
        type = if field.type == :memo, do: ?M, else: ?C
        name = pad(field.name <> <<0>>, 11, 0)

        descriptor =
          <<name::binary-size(11), type, 0::unsigned-little-32, field.length, 0, 0::112>>

        {[descriptors, descriptor], Map.put(offsets, field.name, offset), offset + field.length}
      end)

    rows =
      Enum.map(records, fn record ->
        marker = if record.deleted?, do: 0x2A, else: 0x20

        values =
          fields
          |> Enum.zip(record.values)
          |> Enum.map(fn
            {%{type: :memo}, pointer} -> <<pointer::unsigned-little-32>>
            {%{type: :character, length: length}, value} -> pad(value, length, 0x20)
          end)

        [<<marker>>, values]
      end)

    dbf =
      IO.iodata_to_binary([header, descriptors, <<0x0D>>, rows, Keyword.fetch!(opts, :trailing)])

    {dbf,
     %{
       record_count: record_count,
       header_length: header_length,
       record_length: record_length,
       field_offsets: field_offsets,
       records_offset: header_length
     }}
  end

  defp build_fpt(blocks, next_free_block, block_size, stored_block_size, opts) do
    header_opaque = pad(Keyword.fetch!(opts, :header_opaque), 504, 0)

    header =
      <<next_free_block::unsigned-big-32, 0, 0, stored_block_size::unsigned-big-16,
        header_opaque::binary-size(504)>>

    first_offset = ceil_div(512, block_size) * block_size
    prefix = pad(header, first_offset, 0)
    IO.iodata_to_binary([prefix, Enum.map(blocks, & &1.bytes), Keyword.fetch!(opts, :trailing)])
  end

  defp default_value(:memo), do: nil
  defp default_value(:character), do: ""

  defp pad(binary, size, byte) when is_binary(binary) and byte_size(binary) <= size do
    binary <> :binary.copy(<<byte>>, size - byte_size(binary))
  end

  defp pad(_binary, _size, _byte), do: raise(ArgumentError, "value exceeds fixed width")

  defp truncate(binary, remove_bytes) do
    binary_part(binary, 0, max(byte_size(binary) - remove_bytes, 0))
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
