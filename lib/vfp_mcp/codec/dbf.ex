defmodule VfpMcp.Codec.Dbf.Header do
  @moduledoc "Physical DBF header values with their original bytes and spans."

  @enforce_keys [
    :format,
    :date_bytes,
    :record_count,
    :header_length,
    :record_length,
    :code_page,
    :reserved_bytes,
    :raw_bytes,
    :spans
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          format: non_neg_integer(),
          date_bytes: binary(),
          record_count: non_neg_integer(),
          header_length: pos_integer(),
          record_length: pos_integer(),
          code_page: non_neg_integer(),
          reserved_bytes: %{middle: binary(), suffix: binary()},
          raw_bytes: binary(),
          spans: %{required(atom()) => VfpMcp.Source.Span.t()}
        }
end

defmodule VfpMcp.Codec.Dbf.Field do
  @moduledoc "One DBF field descriptor and its record-relative layout."

  @enforce_keys [
    :index,
    :name,
    :raw_name,
    :type,
    :type_byte,
    :length,
    :decimal_count,
    :flags,
    :address_bytes,
    :reserved_bytes,
    :record_offset,
    :raw_bytes,
    :descriptor_span
  ]
  defstruct @enforce_keys

  @type physical_type :: :character | :memo | :opaque

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          name: binary(),
          raw_name: binary(),
          type: physical_type(),
          type_byte: non_neg_integer(),
          length: pos_integer(),
          decimal_count: non_neg_integer(),
          flags: non_neg_integer(),
          address_bytes: binary(),
          reserved_bytes: binary(),
          record_offset: pos_integer(),
          raw_bytes: binary(),
          descriptor_span: VfpMcp.Source.Span.t()
        }
end

defmodule VfpMcp.Codec.Dbf.FieldValue do
  @moduledoc "A byte-faithful fixed-width value from one physical record."

  @enforce_keys [:field_index, :field_name, :type, :raw_bytes, :span]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          field_index: non_neg_integer(),
          field_name: binary(),
          type: VfpMcp.Codec.Dbf.Field.physical_type(),
          raw_bytes: binary(),
          span: VfpMcp.Source.Span.t()
        }
end

defmodule VfpMcp.Codec.Dbf.Record do
  @moduledoc "A physical DBF record, including deleted and invalid markers."

  @enforce_keys [:index, :marker, :deleted?, :raw_bytes, :span, :marker_span, :values]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          marker: non_neg_integer(),
          deleted?: boolean() | nil,
          raw_bytes: binary(),
          span: VfpMcp.Source.Span.t(),
          marker_span: VfpMcp.Source.Span.t(),
          values: [VfpMcp.Codec.Dbf.FieldValue.t()]
        }
end

defmodule VfpMcp.Codec.Dbf do
  @moduledoc """
  Bounds-checked, loss-aware decoder for the physical DBF member of a pair.

  The decoder performs no text conversion and no filesystem access. Unsupported
  field types remain opaque fixed-width slices so they cannot shift later field
  boundaries.
  """

  # specled covers:
  # - vfp_mcp.codec.dbf_structure
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Codec.Dbf.{Field, FieldValue, Header, Record}
  alias VfpMcp.{Finding, Limits}
  alias VfpMcp.Source.Span

  @fixed_header_size 32
  @descriptor_size 32
  @terminator 0x0D
  @active_marker 0x20
  @deleted_marker 0x2A

  @enforce_keys [
    :bytes,
    :header,
    :fields,
    :records,
    :header_bytes,
    :descriptor_bytes,
    :terminator_span,
    :header_extension_bytes,
    :records_bytes,
    :trailing_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bytes: binary(),
          header: Header.t(),
          fields: [Field.t()],
          records: [Record.t()],
          header_bytes: binary(),
          descriptor_bytes: binary(),
          terminator_span: Span.t(),
          header_extension_bytes: binary(),
          records_bytes: binary(),
          trailing_bytes: binary()
        }

  @type result :: {:ok, t(), [Finding.t()]} | {:error, [Finding.t()]}

  @spec decode(binary(), Limits.t()) :: result()
  def decode(bytes, limits \\ Limits.new!())

  def decode(bytes, %Limits{} = limits) when is_binary(bytes) do
    with {:ok, header} <- decode_header(bytes, limits),
         {:ok, fields, terminator_offset, descriptor_findings} <-
           decode_fields(bytes, header, limits),
         :ok <- validate_schema(fields, header),
         {:ok, records, record_findings} <-
           decode_records(bytes, header, fields, limits, length(descriptor_findings)) do
      record_region_length = header.record_count * header.record_length
      record_end = header.header_length + record_region_length
      trailing_bytes = binary_part(bytes, record_end, byte_size(bytes) - record_end)
      trailing_findings = trailing_findings(trailing_bytes, record_end)
      findings = sort_findings(descriptor_findings ++ record_findings ++ trailing_findings)

      with :ok <- check_finding_limit(findings, limits) do
        dbf = %__MODULE__{
          bytes: bytes,
          header: header,
          fields: fields,
          records: records,
          header_bytes: binary_part(bytes, 0, header.header_length),
          descriptor_bytes:
            binary_part(bytes, @fixed_header_size, terminator_offset - @fixed_header_size),
          terminator_span: Span.new(:dbf, terminator_offset, 1),
          header_extension_bytes:
            binary_part(
              bytes,
              terminator_offset + 1,
              header.header_length - terminator_offset - 1
            ),
          records_bytes: binary_part(bytes, header.header_length, record_region_length),
          trailing_bytes: trailing_bytes
        }

        {:ok, dbf, findings}
      end
    end
  end

  def decode(_bytes, _limits) do
    {:error, [Finding.fatal(:dbf_invalid_input, "DBF input must be a binary and valid limits")]}
  end

  defp decode_header(bytes, _limits) when byte_size(bytes) < @fixed_header_size do
    fatal(:dbf_header_truncated, "DBF header is shorter than 32 bytes", byte_size(bytes), %{
      available: byte_size(bytes),
      required: @fixed_header_size
    })
  end

  defp decode_header(bytes, limits) do
    <<format, date_bytes::binary-size(3), record_count::unsigned-little-32,
      header_length::unsigned-little-16, record_length::unsigned-little-16,
      middle_reserved::binary-size(17), code_page, suffix_reserved::binary-size(2),
      _rest::binary>> = bytes

    record_region_length = record_count * record_length
    record_end = header_length + record_region_length

    cond do
      record_count > limits.records ->
        {:error,
         [
           Finding.fatal(:limit_records_exceeded, "records limit exceeded",
             location: %{member: :dbf, offset: 4},
             evidence: %{actual: record_count, maximum: limits.records}
           )
         ]}

      header_length < @fixed_header_size + 1 ->
        fatal(:dbf_header_length_invalid, "DBF header length is too small", 8, %{
          header_length: header_length
        })

      record_length < 1 ->
        fatal(:dbf_record_length_invalid, "DBF record length is zero", 10, %{})

      header_length > byte_size(bytes) ->
        fatal(:dbf_header_extent_invalid, "DBF header extends beyond the member", 8, %{
          header_length: header_length,
          member_bytes: byte_size(bytes)
        })

      record_end > byte_size(bytes) ->
        fatal(:dbf_record_extent_invalid, "DBF records extend beyond the member", 4, %{
          record_count: record_count,
          record_length: record_length,
          record_end: record_end,
          member_bytes: byte_size(bytes)
        })

      true ->
        {:ok,
         %Header{
           format: format,
           date_bytes: date_bytes,
           record_count: record_count,
           header_length: header_length,
           record_length: record_length,
           code_page: code_page,
           reserved_bytes: %{middle: middle_reserved, suffix: suffix_reserved},
           raw_bytes: binary_part(bytes, 0, @fixed_header_size),
           spans: %{
             format: Span.new(:dbf, 0, 1),
             date: Span.new(:dbf, 1, 3),
             record_count: Span.new(:dbf, 4, 4),
             header_length: Span.new(:dbf, 8, 2),
             record_length: Span.new(:dbf, 10, 2),
             middle_reserved: Span.new(:dbf, 12, 17),
             code_page: Span.new(:dbf, 29, 1),
             suffix_reserved: Span.new(:dbf, 30, 2)
           }
         }}
    end
  end

  defp decode_fields(bytes, header, limits) do
    walk_descriptors(bytes, header, limits, @fixed_header_size, 0, 1, [], [], MapSet.new())
  end

  defp walk_descriptors(
         bytes,
         header,
         limits,
         offset,
         index,
         record_offset,
         fields,
         findings,
         names
       ) do
    cond do
      offset >= header.header_length ->
        fatal(:dbf_descriptor_terminator_missing, "DBF field terminator is missing", offset, %{})

      :binary.at(bytes, offset) == @terminator ->
        {:ok, Enum.reverse(fields), offset, Enum.reverse(findings)}

      index >= limits.fields ->
        {:error,
         [
           Finding.fatal(:limit_fields_exceeded, "fields limit exceeded",
             location: %{member: :dbf, offset: offset},
             evidence: %{actual: index + 1, maximum: limits.fields}
           )
         ]}

      offset + @descriptor_size > header.header_length ->
        fatal(
          :dbf_descriptor_truncated,
          "DBF field descriptor crosses the declared header",
          offset,
          %{header_length: header.header_length}
        )

      true ->
        raw = binary_part(bytes, offset, @descriptor_size)

        <<raw_name::binary-size(11), type_byte, address_bytes::binary-size(4), length,
          decimal_count, flags, reserved_bytes::binary-size(13)>> = raw

        name = decode_name(raw_name)

        type =
          if type_byte == ?C, do: :character, else: if(type_byte == ?M, do: :memo, else: :opaque)

        cond do
          length == 0 ->
            fatal(:dbf_field_zero_length, "DBF field length is zero", offset + 16, %{
              field_index: index,
              field_name: name
            })

          record_offset + length > header.record_length ->
            fatal(:dbf_schema_width_exceeded, "DBF field exceeds the record length", offset, %{
              field_index: index,
              field_name: name,
              record_offset: record_offset,
              field_length: length,
              record_length: header.record_length
            })

          true ->
            field = %Field{
              index: index,
              name: name,
              raw_name: raw_name,
              type: type,
              type_byte: type_byte,
              length: length,
              decimal_count: decimal_count,
              flags: flags,
              address_bytes: address_bytes,
              reserved_bytes: reserved_bytes,
              record_offset: record_offset,
              raw_bytes: raw,
              descriptor_span: Span.new(:dbf, offset, @descriptor_size)
            }

            duplicate? = MapSet.member?(names, canonical_name(name))

            next_findings =
              findings
              |> maybe_add(
                duplicate?,
                :dbf_duplicate_field_name,
                :error,
                :mutation_blocked,
                "duplicate DBF field name",
                offset,
                %{field_index: index, field_name: name}
              )
              |> maybe_add(
                type == :opaque,
                :dbf_unknown_field_type,
                :warning,
                :preserved,
                "unsupported DBF field type is retained as opaque bytes",
                offset + 11,
                %{field_index: index, type_byte: type_byte}
              )

            walk_descriptors(
              bytes,
              header,
              limits,
              offset + @descriptor_size,
              index + 1,
              record_offset + length,
              [field | fields],
              next_findings,
              MapSet.put(names, canonical_name(name))
            )
        end
    end
  end

  defp validate_schema(fields, header) do
    declared_width = 1 + Enum.sum(Enum.map(fields, & &1.length))

    if declared_width == header.record_length do
      :ok
    else
      fatal(:dbf_schema_width_mismatch, "DBF schema width does not match record length", 10, %{
        schema_width: declared_width,
        record_length: header.record_length
      })
    end
  end

  defp decode_records(bytes, header, fields, limits, existing_findings) do
    indices(header.record_count)
    |> Enum.reduce_while({[], [], existing_findings}, fn index,
                                                         {records, findings, finding_count} ->
      offset = header.header_length + index * header.record_length
      raw = binary_part(bytes, offset, header.record_length)
      marker = :binary.at(raw, 0)

      {deleted?, marker_finding} =
        case marker do
          @active_marker ->
            {false, nil}

          @deleted_marker ->
            {true, nil}

          other ->
            {nil,
             Finding.new(
               :dbf_invalid_record_marker,
               :error,
               :mutation_blocked,
               "DBF record marker is neither active nor deleted",
               location: %{member: :dbf, offset: offset},
               evidence: %{marker: other, record: index}
             )}
        end

      if marker_finding && finding_count >= limits.findings do
        {:halt, limit_findings_error(limits, finding_count + 1, offset)}
      else
        values =
          Enum.map(fields, fn field ->
            value_offset = offset + field.record_offset

            %FieldValue{
              field_index: field.index,
              field_name: field.name,
              type: field.type,
              raw_bytes: binary_part(bytes, value_offset, field.length),
              span: Span.new(:dbf, value_offset, field.length)
            }
          end)

        record = %Record{
          index: index,
          marker: marker,
          deleted?: deleted?,
          raw_bytes: raw,
          span: Span.new(:dbf, offset, header.record_length),
          marker_span: Span.new(:dbf, offset, 1),
          values: values
        }

        next_findings = if marker_finding, do: [marker_finding | findings], else: findings
        next_count = if marker_finding, do: finding_count + 1, else: finding_count
        {:cont, {[record | records], next_findings, next_count}}
      end
    end)
    |> case do
      {:error, _findings} = error -> error
      {records, findings, _count} -> {:ok, Enum.reverse(records), Enum.reverse(findings)}
    end
  end

  defp trailing_findings(trailing_bytes, _offset) when trailing_bytes in [<<>>, <<0x1A>>], do: []

  defp trailing_findings(trailing_bytes, offset) do
    [
      Finding.new(
        :dbf_trailing_bytes_preserved,
        :warning,
        :preserved,
        "unusual bytes after the DBF record region are retained",
        location: %{member: :dbf, offset: offset},
        evidence: %{bytes: byte_size(trailing_bytes)}
      )
    ]
  end

  defp check_finding_limit(findings, limits) do
    if length(findings) <= limits.findings do
      :ok
    else
      limit_findings_error(limits, length(findings), 0)
    end
  end

  defp limit_findings_error(limits, actual, offset) do
    {:error,
     [
       Finding.fatal(:limit_findings_exceeded, "findings limit exceeded",
         location: %{member: :dbf, offset: offset},
         evidence: %{actual: actual, maximum: limits.findings}
       )
     ]}
  end

  defp maybe_add(findings, false, _code, _severity, _impact, _message, _offset, _evidence),
    do: findings

  defp maybe_add(findings, true, code, severity, impact, message, offset, evidence) do
    [
      Finding.new(code, severity, impact, message,
        location: %{member: :dbf, offset: offset},
        evidence: evidence
      )
      | findings
    ]
  end

  defp fatal(code, message, offset, evidence) do
    {:error,
     [
       Finding.fatal(code, message,
         location: %{member: :dbf, offset: offset},
         evidence: evidence
       )
     ]}
  end

  defp decode_name(raw_name) do
    raw_name
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 != 0))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == 0x20))
    |> Enum.reverse()
    |> :erlang.list_to_binary()
  end

  defp canonical_name(name) do
    if String.valid?(name), do: String.downcase(name), else: name
  end

  defp indices(0), do: []
  defp indices(count), do: 0..(count - 1)

  defp sort_findings(findings) do
    Enum.sort_by(findings, fn finding ->
      {Atom.to_string(finding.code), inspect(finding.location), inspect(finding.evidence)}
    end)
  end
end
