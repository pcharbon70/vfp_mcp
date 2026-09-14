defmodule VfpMcp.Codec.Methods.Method do
  @moduledoc "A named PROCEDURE/ENDPROC block with exact source spans."

  alias VfpMcp.Source.Span

  @enforce_keys [
    :index,
    :name,
    :canonical_name,
    :signature_text,
    :declaration,
    :body,
    :body_bytes,
    :terminator,
    :raw_bytes,
    :raw_text,
    :byte_span,
    :text_span,
    :declaration_span,
    :body_span,
    :terminator_span,
    :edit_eligibility
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          name: String.t(),
          canonical_name: String.t(),
          signature_text: String.t(),
          declaration: binary(),
          body: String.t(),
          body_bytes: binary(),
          terminator: binary(),
          raw_bytes: binary(),
          raw_text: String.t(),
          byte_span: Span.t(),
          text_span: map(),
          declaration_span: Span.t(),
          body_span: Span.t(),
          terminator_span: Span.t(),
          edit_eligibility: :eligible | {:blocked, [atom()]}
        }
end

defmodule VfpMcp.Codec.Methods.Memo do
  @moduledoc "Verbatim METHODS memo plus its named block index."

  alias VfpMcp.Codec.Methods.Method
  alias VfpMcp.Source.Span

  @enforce_keys [
    :record_index,
    :raw_bytes,
    :text,
    :span,
    :line_ending,
    :methods,
    :edit_eligibility
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          record_index: non_neg_integer(),
          raw_bytes: binary(),
          text: String.t(),
          span: Span.t(),
          line_ending: :none | :crlf | :lf | :cr | :mixed,
          methods: [Method.t()],
          edit_eligibility: :eligible | {:blocked, [atom()]}
        }
end

defmodule VfpMcp.Codec.Methods do
  @moduledoc """
  Conservative indexer for named Visual FoxPro procedure blocks.

  Markers are recognized only at the start of non-comment lines. Malformed,
  nested, unmatched, and duplicate structures remain verbatim and are blocked
  from named-method targeting.
  """

  # specled covers:
  # - vfp_mcp.codec.method_edit_scope
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.Codec.Methods.{Memo, Method}
  alias VfpMcp.Codec.SemanticText
  alias VfpMcp.{Finding, SourceObject}
  alias VfpMcp.Source.Span

  @procedure ~r/^PROCEDURE[ \t]+([A-Za-z_][A-Za-z0-9_.]*)(.*)$/i
  @endproc ~r/^ENDPROC(?:[ \t]*(?:&&.*)?)?$/i

  @spec attach([SourceObject.t()], [TextValue.t()], atom()) ::
          {:ok, [SourceObject.t()], [Finding.t()]}
  def attach(objects, text_views, encoding) do
    views =
      Enum.filter(text_views, fn view ->
        view.source == :memo and canonical(view.field) == "methods"
      end)
      |> Enum.group_by(& &1.record_index)

    {objects, findings} =
      Enum.map_reduce(objects, [], fn object, findings ->
        case Map.get(views, object.record_index, []) do
          [] ->
            {object, findings}

          [%TextValue{text: text} = view] when is_binary(text) and not is_nil(encoding) ->
            {memo, memo_findings} = parse(view, encoding)
            {%{object | method_memo: memo, methods: memo.methods}, findings ++ memo_findings}

          ambiguous ->
            finding =
              Finding.new(
                :method_memo_ambiguous,
                :error,
                :mutation_blocked,
                "object has multiple or undecodable METHODS memo views",
                location: %{record: object.record_index, field: "METHODS"},
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
    {methods, findings, open} = scan(lines, view, encoding, [], [], nil)

    {methods, findings} =
      case open do
        nil ->
          {methods, findings}

        %{line: line, name: name} ->
          {methods,
           findings ++
             [
               Finding.new(
                 :method_missing_endproc,
                 :error,
                 :mutation_blocked,
                 "PROCEDURE block has no matching ENDPROC",
                 location: %{member: line.content_span.member, offset: line.content_span.offset},
                 evidence: %{record: view.record_index, method: canonical(name)}
               )
             ]}
      end

    {methods, duplicate_findings} = mark_duplicates(methods, view.record_index)
    findings = findings ++ duplicate_findings

    eligibility =
      findings
      |> Enum.filter(&(&1.impact == :mutation_blocked))
      |> Enum.map(& &1.code)
      |> blocked()

    {%Memo{
       record_index: view.record_index,
       raw_bytes: view.raw_bytes,
       text: text,
       span: span,
       line_ending: SemanticText.line_ending(lines),
       methods: methods,
       edit_eligibility: eligibility
     }, findings}
  end

  defp scan([], _view, _encoding, methods, findings, open),
    do: {Enum.reverse(methods), findings, open}

  defp scan([line | rest], view, encoding, methods, findings, open) do
    case marker(line.content_text) do
      {:procedure, name, signature} when is_nil(open) ->
        scan(rest, view, encoding, methods, findings, %{
          line: line,
          name: name,
          signature: signature
        })

      {:procedure, nested_name, _signature} ->
        finding =
          Finding.new(
            :method_nested_procedure,
            :error,
            :mutation_blocked,
            "nested PROCEDURE marker makes method boundaries ambiguous",
            location: %{member: line.content_span.member, offset: line.content_span.offset},
            evidence: %{record: view.record_index, method: canonical(nested_name)}
          )

        scan(rest, view, encoding, methods, findings ++ [finding], open)

      :endproc when is_nil(open) ->
        finding =
          Finding.new(
            :method_unmatched_endproc,
            :error,
            :mutation_blocked,
            "ENDPROC has no preceding PROCEDURE marker",
            location: %{member: line.content_span.member, offset: line.content_span.offset},
            evidence: %{record: view.record_index, line: line.index}
          )

        scan(rest, view, encoding, methods, findings ++ [finding], nil)

      :endproc ->
        method = build_method(open, line, view, encoding, length(methods))
        scan(rest, view, encoding, [method | methods], findings, nil)

      :none ->
        scan(rest, view, encoding, methods, findings, open)
    end
  end

  defp marker(text) do
    trimmed = String.trim_leading(text)

    cond do
      String.starts_with?(trimmed, "*") or String.starts_with?(trimmed, "&&") ->
        :none

      match = Regex.run(@procedure, trimmed) ->
        [_all, name, signature] = match
        {:procedure, name, signature}

      Regex.match?(@endproc, trimmed) ->
        :endproc

      true ->
        :none
    end
  end

  defp build_method(open, ending_line, view, encoding, index) do
    start_offset = open.line.relative_offset
    end_offset = ending_line.relative_offset + byte_size(ending_line.raw_bytes)
    length = end_offset - start_offset
    raw = binary_part(view.raw_bytes, start_offset, length)
    declaration = open.line.raw_bytes
    body_start = start_offset + byte_size(declaration)
    body_length = ending_line.relative_offset - body_start
    body = binary_part(view.raw_bytes, body_start, body_length)
    terminator = ending_line.raw_bytes

    %Method{
      index: index,
      name: open.name,
      canonical_name: canonical(open.name),
      signature_text: open.signature,
      declaration: declaration,
      body: decode!(body, encoding),
      body_bytes: body,
      terminator: terminator,
      raw_bytes: raw,
      raw_text: decode!(raw, encoding),
      byte_span: Span.new(view.span.member, view.span.offset + start_offset, length),
      text_span: SemanticText.text_span(view.raw_bytes, start_offset, length, encoding),
      declaration_span:
        Span.new(view.span.member, view.span.offset + start_offset, byte_size(declaration)),
      body_span: Span.new(view.span.member, view.span.offset + body_start, body_length),
      terminator_span:
        Span.new(
          view.span.member,
          view.span.offset + ending_line.relative_offset,
          byte_size(terminator)
        ),
      edit_eligibility: :eligible
    }
  end

  defp mark_duplicates(methods, record_index) do
    counts = Enum.frequencies_by(methods, & &1.canonical_name)

    methods =
      Enum.map(methods, fn method ->
        if Map.fetch!(counts, method.canonical_name) > 1 do
          %{method | edit_eligibility: {:blocked, [:method_duplicate_name]}}
        else
          method
        end
      end)

    findings =
      for {name, count} <- counts, count > 1 do
        first = Enum.find(methods, &(&1.canonical_name == name))

        Finding.new(
          :method_duplicate_name,
          :error,
          :mutation_blocked,
          "method name occurs more than once in one memo",
          location: %{member: first.byte_span.member, offset: first.byte_span.offset},
          evidence: %{record: record_index, method: name, count: count}
        )
      end

    {methods, findings}
  end

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
