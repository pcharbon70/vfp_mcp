defmodule VfpMcp.Codec.Encoding.TextValue do
  @moduledoc "A decoded UTF-8 view that retains its exact source bytes and span."

  @enforce_keys [:source, :record_index, :field, :raw_bytes, :text, :span]
  defstruct @enforce_keys ++ [:block_type]

  @type t :: %__MODULE__{
          source: :field | :memo,
          record_index: non_neg_integer(),
          field: binary(),
          block_type: non_neg_integer() | nil,
          raw_bytes: binary(),
          text: String.t() | nil,
          span: VfpMcp.Source.Span.t()
        }
end

defmodule VfpMcp.Codec.Encoding do
  @moduledoc """
  Explicit, strict text conversion at the physical codec boundary.

  Windows-1252 is initially supported for both reads and writes. Undefined
  bytes and unrepresentable Unicode code points return findings without partial
  or replacement output.
  """

  # specled covers:
  # - vfp_mcp.codec.lossless_encoding
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.codec.reject_unrepresentable_text

  alias VfpMcp.Codec.{Dbf, Fpt}
  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.{Finding, Limits}
  alias VfpMcp.Source.Span

  @windows_1252_drivers [0x03, 0x57]
  @undefined_windows_1252 [0x81, 0x8D, 0x8F, 0x90, 0x9D]

  @decode_special %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }
  @encode_special Map.new(@decode_special, fn {byte, codepoint} -> {codepoint, byte} end)

  @type encoding :: :windows_1252
  @type resolution :: {:ok, encoding() | nil, [Finding.t()]}

  @spec resolve(non_neg_integer(), encoding() | nil) :: resolution()
  def resolve(code_page, expected \\ nil)

  def resolve(code_page, expected)
      when is_integer(code_page) and code_page in 0..255 and
             expected in [nil, :windows_1252] do
    source = if code_page in @windows_1252_drivers, do: :windows_1252, else: nil

    cond do
      is_nil(source) ->
        {:ok, nil,
         [
           finding(
             :codec_unsupported_code_page,
             "DBF code-page metadata is unsupported",
             %{member: :dbf, offset: 29},
             %{code_page: code_page}
           )
         ]}

      expected && expected != source ->
        {:ok, nil,
         [
           finding(
             :codec_conflicting_code_page,
             "declared text encoding conflicts with DBF metadata",
             %{member: :dbf, offset: 29},
             %{code_page: code_page, expected: expected, source: source}
           )
         ]}

      true ->
        {:ok, source, []}
    end
  end

  def resolve(code_page, expected) do
    {:ok, nil,
     [
       finding(
         :codec_conflicting_code_page,
         "code-page resolution inputs are invalid",
         %{member: :dbf, offset: 29},
         %{code_page: inspect(code_page), expected: inspect(expected)}
       )
     ]}
  end

  @spec decode(binary(), encoding(), keyword()) :: {:ok, String.t()} | {:error, Finding.t()}
  def decode(bytes, encoding, opts \\ [])

  def decode(bytes, :windows_1252, opts) when is_binary(bytes) and is_list(opts) do
    location = Keyword.get(opts, :location)

    bytes
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {byte, index}, acc ->
      if byte in @undefined_windows_1252 do
        {:halt,
         {:error,
          finding(
            :codec_invalid_text_bytes,
            "Windows-1252 input contains an undefined byte",
            advance_location(location, index),
            %{byte: byte, relative_offset: index}
          )}}
      else
        codepoint = Map.get(@decode_special, byte, byte)
        {:cont, [<<codepoint::utf8>> | acc]}
      end
    end)
    |> case do
      {:error, %Finding{}} = error -> error
      reversed -> {:ok, reversed |> Enum.reverse() |> IO.iodata_to_binary()}
    end
  end

  def decode(_bytes, _encoding, _opts) do
    {:error, finding(:codec_unsupported_code_page, "text decoder is unavailable", nil, %{})}
  end

  @spec encode(binary(), encoding()) :: {:ok, binary()} | {:error, Finding.t()}
  def encode(text, :windows_1252) when is_binary(text) do
    if String.valid?(text) do
      text
      |> String.to_charlist()
      |> Enum.with_index()
      |> Enum.reduce_while([], fn {codepoint, index}, acc ->
        case encode_codepoint(codepoint) do
          {:ok, byte} ->
            {:cont, [byte | acc]}

          :error ->
            {:halt,
             {:error,
              finding(
                :codec_unrepresentable_text,
                "text cannot be represented losslessly in Windows-1252",
                nil,
                %{codepoint: codepoint, character_index: index}
              )}}
        end
      end)
      |> case do
        {:error, %Finding{}} = error -> error
        reversed -> {:ok, reversed |> Enum.reverse() |> :erlang.list_to_binary()}
      end
    else
      {:error, finding(:codec_invalid_utf8, "text to encode is not valid UTF-8", nil, %{})}
    end
  end

  def encode(_text, _encoding) do
    {:error, finding(:codec_unsupported_code_page, "text encoder is unavailable", nil, %{})}
  end

  @spec decode_physical(Dbf.t(), Fpt.t(), encoding() | nil, Limits.t()) ::
          {:ok, [TextValue.t()], [Finding.t()]} | {:error, [Finding.t()]}
  def decode_physical(%Dbf{} = dbf, %Fpt{} = fpt, encoding, %Limits{} = limits) do
    sources = field_sources(dbf) ++ memo_sources(fpt)
    total_bytes = Enum.sum(Enum.map(sources, fn source -> byte_size(source.raw_bytes) end))

    with :ok <- Limits.check(limits, :parsed_text_bytes, total_bytes) do
      if is_nil(encoding) do
        {:ok, [], []}
      else
        {views, findings} =
          Enum.map_reduce(sources, [], fn source, findings ->
            case decode(source.raw_bytes, encoding, location: source.span) do
              {:ok, text} ->
                {%TextValue{
                   source: source.source,
                   record_index: source.record_index,
                   field: source.field,
                   block_type: Map.get(source, :block_type),
                   raw_bytes: source.raw_bytes,
                   text: text,
                   span: source.span
                 }, findings}

              {:error, finding} ->
                {%TextValue{
                   source: source.source,
                   record_index: source.record_index,
                   field: source.field,
                   block_type: Map.get(source, :block_type),
                   raw_bytes: source.raw_bytes,
                   text: nil,
                   span: source.span
                 }, [finding | findings]}
            end
          end)

        {:ok, views, Enum.reverse(findings)}
      end
    else
      {:error, %Finding{} = finding} -> {:error, [finding]}
    end
  end

  defp field_sources(dbf) do
    for record <- dbf.records,
        value <- record.values,
        value.type == :character do
      %{
        source: :field,
        record_index: record.index,
        field: value.field_name,
        raw_bytes: value.raw_bytes,
        span: value.span
      }
    end
  end

  defp memo_sources(fpt) do
    for memo_ref <- fpt.memo_refs,
        memo_ref.resolution == :resolved,
        memo_ref.block_type == 1 do
      %{
        source: :memo,
        record_index: memo_ref.record_index,
        field: memo_ref.field,
        block_type: memo_ref.block_type,
        raw_bytes: memo_ref.payload_bytes,
        span: memo_ref.payload_span
      }
    end
  end

  defp encode_codepoint(codepoint) when codepoint in 0x00..0x7F, do: {:ok, codepoint}
  defp encode_codepoint(codepoint) when codepoint in 0xA0..0xFF, do: {:ok, codepoint}

  defp encode_codepoint(codepoint) do
    case Map.fetch(@encode_special, codepoint) do
      {:ok, byte} -> {:ok, byte}
      :error -> :error
    end
  end

  defp advance_location(%Span{} = span, relative_offset) do
    %{member: span.member, offset: span.offset + relative_offset}
  end

  defp advance_location(location, _relative_offset), do: location

  defp finding(code, message, location, evidence) do
    Finding.new(code, :error, :mutation_blocked, message,
      location: location,
      evidence: evidence
    )
  end
end
