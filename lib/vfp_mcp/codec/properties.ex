defmodule VfpMcp.Codec.Properties.Assignment do
  @moduledoc "One property line with its semantic value and verbatim representation."

  alias VfpMcp.Source.Span

  @enforce_keys [
    :index,
    :kind,
    :raw_bytes,
    :raw_text,
    :line_ending,
    :byte_span,
    :text_span,
    :edit_eligibility
  ]
  defstruct @enforce_keys ++
              [
                :name,
                :canonical_name,
                :raw_literal,
                :literal_kind,
                :value,
                :separators,
                :name_span,
                :literal_span,
                :literal_text_span
              ]

  @type kind :: :assignment | :comment | :blank | :continuation | :unsupported
  @type eligibility :: :eligible | {:blocked, [atom()]}

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          kind: kind(),
          raw_bytes: binary(),
          raw_text: String.t(),
          line_ending: binary(),
          byte_span: Span.t(),
          text_span: map(),
          edit_eligibility: eligibility(),
          name: String.t() | nil,
          canonical_name: String.t() | nil,
          raw_literal: binary() | nil,
          literal_kind: atom() | nil,
          value: term(),
          separators: map() | nil,
          name_span: Span.t() | nil,
          literal_span: Span.t() | nil,
          literal_text_span: map() | nil
        }
end

defmodule VfpMcp.Codec.Properties.Memo do
  @moduledoc "Verbatim PROPERTIES memo plus its conservative line index."

  alias VfpMcp.Codec.Properties.Assignment
  alias VfpMcp.Source.Span

  @enforce_keys [
    :record_index,
    :raw_bytes,
    :text,
    :span,
    :line_ending,
    :entries,
    :edit_eligibility
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          record_index: non_neg_integer(),
          raw_bytes: binary(),
          text: String.t(),
          span: Span.t(),
          line_ending: :none | :crlf | :lf | :cr | :mixed,
          entries: [Assignment.t()],
          edit_eligibility: Assignment.eligibility()
        }
end

defmodule VfpMcp.Codec.Properties do
  @moduledoc """
  Conservative parser for line-oriented Visual FoxPro PROPERTIES memos.

  Recognized literals receive semantic values and exact source spans. Every
  other line remains verbatim and is explicitly ineligible for a typed edit.
  """

  # specled covers:
  # - vfp_mcp.codec.property_edit_scope
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.Codec.Properties.{Assignment, Memo}
  alias VfpMcp.Codec.SemanticText
  alias VfpMcp.{Finding, SourceObject}
  alias VfpMcp.Source.Span

  @assignment ~r/^([A-Za-z_][A-Za-z0-9_.]*)([ \t]*)(=)([ \t]*)(.*)$/
  @integer ~r/^[+-]?[0-9]+$/
  @decimal ~r/^[+-]?(?:[0-9]+\.[0-9]*|[0-9]*\.[0-9]+)$/
  @string ~r/^"(?:""|[^"])*"$/s
  @date ~r/^\{\^([0-9]{4}-[0-9]{2}-[0-9]{2})\}$/
  @datetime ~r/^\{\^([0-9]{4}-[0-9]{2}-[0-9]{2})[ T]([0-9]{2}:[0-9]{2}:[0-9]{2})\}$/

  @spec attach([SourceObject.t()], [TextValue.t()], atom()) ::
          {:ok, [SourceObject.t()], [Finding.t()]}
  def attach(objects, text_views, encoding) do
    views =
      Enum.filter(text_views, fn view ->
        view.source == :memo and canonical(view.field) == "properties"
      end)
      |> Enum.group_by(& &1.record_index)

    {objects, findings} =
      Enum.map_reduce(objects, [], fn object, findings ->
        case Map.get(views, object.record_index, []) do
          [] ->
            {object, findings}

          [%TextValue{text: text} = view] when is_binary(text) and not is_nil(encoding) ->
            {memo, memo_findings} = parse(view, encoding)
            {%{object | property_memo: memo, properties: memo.entries}, findings ++ memo_findings}

          ambiguous ->
            finding =
              Finding.new(
                :property_memo_ambiguous,
                :error,
                :mutation_blocked,
                "object has multiple or undecodable PROPERTIES memo views",
                location: %{record: object.record_index, field: "PROPERTIES"},
                evidence: %{views: length(ambiguous)}
              )

            {object, findings ++ [finding]}
        end
      end)

    {:ok, objects, findings}
  end

  @spec parse(TextValue.t(), atom()) :: {Memo.t(), [Finding.t()]}
  def parse(%TextValue{source: :memo, text: text, span: %Span{} = span} = view, encoding)
      when is_binary(text) and not is_nil(encoding) do
    lines = SemanticText.lines(view.raw_bytes, span, encoding)

    {entries, findings} =
      Enum.map_reduce(lines, [], fn line, findings ->
        {entry, entry_findings} = parse_line(line, view, encoding)
        {entry, findings ++ entry_findings}
      end)

    {entries, duplicate_findings} = mark_duplicates(entries, view.record_index)
    findings = findings ++ duplicate_findings

    eligibility =
      blocked(
        findings
        |> Enum.filter(&(&1.impact == :mutation_blocked))
        |> Enum.map(& &1.code)
      )

    {%Memo{
       record_index: view.record_index,
       raw_bytes: view.raw_bytes,
       text: text,
       span: span,
       line_ending: SemanticText.line_ending(lines),
       entries: entries,
       edit_eligibility: eligibility
     }, findings}
  end

  defp parse_line(line, view, encoding) do
    trimmed = String.trim_leading(line.content_text)

    cond do
      String.trim(line.content_text) == "" ->
        {base_entry(line, :blank, :property_blank_line), []}

      String.starts_with?(trimmed, "*") or String.starts_with?(trimmed, "&&") ->
        {base_entry(line, :comment, :property_comment), []}

      String.ends_with?(String.trim_trailing(line.content_text), ";") ->
        entry = base_entry(line, :continuation, :property_continuation)
        {entry, [preserved_finding(:property_continuation, line, view.record_index)]}

      true ->
        parse_assignment(line, view, encoding)
    end
  end

  defp parse_assignment(line, view, encoding) do
    case Regex.run(@assignment, line.content_bytes, return: :index) do
      [{0, _full}, name_index, before_index, equals_index, after_index, literal_index] ->
        name = slice(line.content_bytes, name_index)
        before_equals = slice(line.content_bytes, before_index)
        equals = slice(line.content_bytes, equals_index)
        after_equals = slice(line.content_bytes, after_index)
        raw_literal = slice(line.content_bytes, literal_index)

        {literal_kind, value, literal_findings} =
          parse_literal(raw_literal, line, view, literal_index, encoding)

        literal_offset = elem(literal_index, 0)
        literal_length = elem(literal_index, 1)

        eligibility =
          blocked(Enum.map(literal_findings, & &1.code))

        entry = %Assignment{
          index: line.index,
          kind: :assignment,
          name: name,
          canonical_name: canonical(name),
          raw_literal: raw_literal,
          literal_kind: literal_kind,
          value: value,
          separators: %{
            before_equals: before_equals,
            equals: equals,
            after_equals: after_equals
          },
          raw_bytes: line.raw_bytes,
          raw_text: line.content_text <> decode!(line.ending_bytes, encoding),
          line_ending: line.ending_bytes,
          byte_span: line.span,
          text_span: line.text_span,
          name_span: absolute_span(line, elem(name_index, 0), elem(name_index, 1)),
          literal_span: absolute_span(line, literal_offset, literal_length),
          literal_text_span:
            SemanticText.text_span(
              view.raw_bytes,
              line.relative_offset + literal_offset,
              literal_length,
              encoding
            ),
          edit_eligibility: eligibility
        }

        {entry, literal_findings}

      _no_assignment ->
        entry = base_entry(line, :unsupported, :property_unsupported_line)
        {entry, [preserved_finding(:property_unsupported_line, line, view.record_index)]}
    end
  end

  defp parse_literal(raw, line, view, literal_index, encoding) do
    text = decode!(raw, encoding)
    location = literal_location(line, literal_index)

    cond do
      Regex.match?(@string, text) ->
        inner = binary_part(text, 1, byte_size(text) - 2)
        {:string, String.replace(inner, "\"\"", "\""), []}

      String.starts_with?(text, "\"") ->
        {:malformed_string, nil,
         [
           Finding.new(
             :property_malformed_string,
             :error,
             :mutation_blocked,
             "property string literal is not terminated unambiguously",
             location: location,
             evidence: %{record: view.record_index}
           )
         ]}

      String.upcase(text) == ".T." ->
        {:boolean, true, []}

      String.upcase(text) == ".F." ->
        {:boolean, false, []}

      String.upcase(text) == ".NULL." ->
        {:null, nil, []}

      Regex.match?(@integer, text) ->
        {:integer, String.to_integer(text), []}

      Regex.match?(@decimal, text) ->
        {:decimal, {:decimal, text}, []}

      match = Regex.run(@datetime, text) ->
        [_all, date, time] = match

        case NaiveDateTime.from_iso8601(date <> "T" <> time) do
          {:ok, value} -> {:datetime, {:datetime, value}, []}
          {:error, _reason} -> unsupported_literal(text, location, view.record_index)
        end

      match = Regex.run(@date, text) ->
        [_all, date] = match

        case Date.from_iso8601(date) do
          {:ok, value} -> {:date, {:date, value}, []}
          {:error, _reason} -> unsupported_literal(text, location, view.record_index)
        end

      true ->
        unsupported_literal(text, location, view.record_index)
    end
  end

  defp unsupported_literal(_text, location, record_index) do
    {:unsupported, nil,
     [
       Finding.new(
         :property_unsupported_literal,
         :warning,
         :preserved,
         "property literal is preserved without semantic interpretation",
         location: location,
         evidence: %{record: record_index}
       )
     ]}
  end

  defp mark_duplicates(entries, record_index) do
    counts =
      entries
      |> Enum.filter(&(&1.kind == :assignment))
      |> Enum.frequencies_by(& &1.canonical_name)

    duplicate_names = for {name, count} <- counts, count > 1, do: {name, count}

    entries =
      Enum.map(entries, fn entry ->
        case Map.get(counts, entry.canonical_name, 0) do
          count when count > 1 ->
            %{entry | edit_eligibility: {:blocked, [:property_duplicate_assignment]}}

          _count ->
            entry
        end
      end)

    findings =
      Enum.map(duplicate_names, fn {name, count} ->
        first = Enum.find(entries, &(&1.canonical_name == name))

        Finding.new(
          :property_duplicate_assignment,
          :error,
          :mutation_blocked,
          "property name occurs more than once in one memo",
          location: %{member: first.byte_span.member, offset: first.byte_span.offset},
          evidence: %{record: record_index, property: name, count: count}
        )
      end)

    {entries, findings}
  end

  defp base_entry(line, kind, blocked_code) do
    %Assignment{
      index: line.index,
      kind: kind,
      raw_bytes: line.raw_bytes,
      raw_text: line.content_text <> line.ending_bytes,
      line_ending: line.ending_bytes,
      byte_span: line.span,
      text_span: line.text_span,
      edit_eligibility: {:blocked, [blocked_code]}
    }
  end

  defp preserved_finding(code, line, record_index) do
    Finding.new(
      code,
      :warning,
      :preserved,
      "property syntax is retained verbatim and not interpreted",
      location: %{member: line.content_span.member, offset: line.content_span.offset},
      evidence: %{record: record_index, line: line.index}
    )
  end

  defp literal_location(line, {offset, _length}),
    do: %{member: line.content_span.member, offset: line.content_span.offset + offset}

  defp absolute_span(line, offset, length),
    do: Span.new(line.content_span.member, line.content_span.offset + offset, length)

  defp slice(bytes, {offset, length}), do: binary_part(bytes, offset, length)
  defp canonical(name), do: String.downcase(name)

  defp blocked(codes) do
    codes = codes |> Enum.uniq() |> Enum.sort()
    if codes == [], do: :eligible, else: {:blocked, codes}
  end

  defp decode!(bytes, encoding) do
    {:ok, text} = VfpMcp.Codec.Encoding.decode(bytes, encoding)
    text
  end
end
