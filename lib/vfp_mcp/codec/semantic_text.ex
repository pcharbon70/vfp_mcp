defmodule VfpMcp.Codec.SemanticText.Line do
  @moduledoc false

  @enforce_keys [
    :index,
    :relative_offset,
    :content_bytes,
    :ending_bytes,
    :raw_bytes,
    :content_text,
    :span,
    :content_span,
    :text_span
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          relative_offset: non_neg_integer(),
          content_bytes: binary(),
          ending_bytes: binary(),
          raw_bytes: binary(),
          content_text: String.t(),
          span: VfpMcp.Source.Span.t(),
          content_span: VfpMcp.Source.Span.t(),
          text_span: %{offset: non_neg_integer(), length: non_neg_integer()}
        }
end

defmodule VfpMcp.Codec.SemanticText do
  @moduledoc false

  alias VfpMcp.Codec.Encoding
  alias VfpMcp.Codec.SemanticText.Line
  alias VfpMcp.Source.Span

  @spec lines(binary(), Span.t(), Encoding.encoding()) :: [Line.t()]
  def lines(<<>>, %Span{}, _encoding), do: []

  def lines(raw_bytes, %Span{} = source_span, encoding) do
    raw_bytes
    |> split_lines(0, [])
    |> Enum.with_index()
    |> Enum.map(fn {{relative_offset, content, ending}, index} ->
      raw = content <> ending

      %Line{
        index: index,
        relative_offset: relative_offset,
        content_bytes: content,
        ending_bytes: ending,
        raw_bytes: raw,
        content_text: decode!(content, encoding),
        span: Span.new(source_span.member, source_span.offset + relative_offset, byte_size(raw)),
        content_span:
          Span.new(source_span.member, source_span.offset + relative_offset, byte_size(content)),
        text_span: text_span(raw_bytes, relative_offset, byte_size(raw), encoding)
      }
    end)
  end

  @spec text_span(binary(), non_neg_integer(), non_neg_integer(), Encoding.encoding()) :: map()
  def text_span(raw_bytes, offset, length, encoding) do
    prefix = binary_part(raw_bytes, 0, offset)
    selected = binary_part(raw_bytes, offset, length)

    %{
      offset: prefix |> decode!(encoding) |> byte_size(),
      length: selected |> decode!(encoding) |> byte_size()
    }
  end

  @spec line_ending([Line.t()]) :: :none | :crlf | :lf | :cr | :mixed
  def line_ending(lines) do
    styles =
      lines
      |> Enum.map(& &1.ending_bytes)
      |> Enum.reject(&(&1 == <<>>))
      |> Enum.map(fn
        "\r\n" -> :crlf
        "\n" -> :lf
        "\r" -> :cr
      end)
      |> Enum.uniq()

    case styles do
      [] -> :none
      [style] -> style
      _multiple -> :mixed
    end
  end

  defp split_lines(bytes, offset, acc) do
    case find_ending(bytes, 0) do
      :none ->
        Enum.reverse([{offset, bytes, <<>>} | acc])

      {content_length, ending_length} ->
        content = binary_part(bytes, 0, content_length)
        ending = binary_part(bytes, content_length, ending_length)
        consumed = content_length + ending_length
        rest = binary_part(bytes, consumed, byte_size(bytes) - consumed)
        next_acc = [{offset, content, ending} | acc]

        if rest == <<>> do
          Enum.reverse(next_acc)
        else
          split_lines(rest, offset + consumed, next_acc)
        end
    end
  end

  defp find_ending(bytes, index) when index >= byte_size(bytes), do: :none

  defp find_ending(bytes, index) do
    case binary_part(bytes, index, min(2, byte_size(bytes) - index)) do
      <<13, 10>> -> {index, 2}
      <<13, _rest::binary>> -> {index, 1}
      <<10, _rest::binary>> -> {index, 1}
      _other -> find_ending(bytes, index + 1)
    end
  end

  defp decode!(bytes, encoding) do
    {:ok, text} = Encoding.decode(bytes, encoding)
    text
  end
end
