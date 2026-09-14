defmodule VfpMcp.Codec.MethodsTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.{Encoding, Methods}
  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.Source.Span

  # specled covers:
  # - vfp_mcp.codec.method_edit_scope
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  test "indexes named blocks while ignoring marker phrases in comments and strings" do
    raw =
      IO.iodata_to_binary([
        "* PROCEDURE Fake\r\n",
        "PROCEDURE Init(tcName)\r\n",
        "  value = \"ENDPROC and Caf",
        <<0xE9>>,
        "\"\r\n",
        "  && ENDPROC\r\n",
        "ENDPROC\r\n",
        "procedure Click\r\n",
        "  ? \"PROCEDURE Fake\"\r\n",
        "endproc\r\n"
      ])

    {memo, findings} = Methods.parse(view(raw), :windows_1252)

    assert findings == []
    assert memo.raw_bytes == raw
    assert memo.line_ending == :crlf
    assert memo.edit_eligibility == :eligible

    assert Enum.map(memo.methods, &{&1.name, &1.signature_text}) == [
             {"Init", "(tcName)"},
             {"Click", ""}
           ]

    [init, click] = memo.methods
    assert init.declaration == "PROCEDURE Init(tcName)\r\n"
    assert init.terminator == "ENDPROC\r\n"
    assert init.body =~ "ENDPROC and Café"
    assert init.body =~ "&& ENDPROC"
    assert slice(raw, init.byte_span, memo.span) == init.raw_bytes
    assert slice(raw, init.declaration_span, memo.span) == init.declaration
    assert slice(raw, init.body_span, memo.span) == init.body_bytes
    assert slice(raw, init.terminator_span, memo.span) == init.terminator

    {click_offset, _length} = :binary.match(raw, "procedure Click")
    assert click.byte_span.offset == memo.span.offset + click_offset
    assert click.text_span.offset == click_offset + 1
  end

  test "reports duplicate, nested, unmatched, and unterminated structure without repair" do
    raw =
      "PROCEDURE Click\nENDPROC\n" <>
        "procedure CLICK\r\nENDPROC\r\n" <>
        "PROCEDURE Outer\nPROCEDURE Inner\nENDPROC\nENDPROC\n" <>
        "PROCEDURE Lost\n"

    {memo, findings} = Methods.parse(view(raw), :windows_1252)

    assert memo.raw_bytes == raw
    assert memo.line_ending == :mixed
    assert Enum.map(memo.methods, & &1.name) == ["Click", "CLICK", "Outer"]

    [first, second | _rest] = memo.methods
    assert first.edit_eligibility == {:blocked, [:method_duplicate_name]}
    assert second.edit_eligibility == {:blocked, [:method_duplicate_name]}

    codes = Enum.map(findings, & &1.code)
    assert :method_duplicate_name in codes
    assert :method_nested_procedure in codes
    assert :method_unmatched_endproc in codes
    assert :method_missing_endproc in codes
    assert match?({:blocked, _codes}, memo.edit_eligibility)
  end

  test "empty method memos remain empty and inspectable" do
    {memo, findings} = Methods.parse(view(<<>>), :windows_1252)
    assert findings == []
    assert memo.methods == []
    assert memo.raw_bytes == <<>>
    assert memo.line_ending == :none
  end

  defp view(raw) do
    {:ok, text} = Encoding.decode(raw, :windows_1252)

    %TextValue{
      source: :memo,
      record_index: 4,
      field: "METHODS",
      block_type: 1,
      raw_bytes: raw,
      text: text,
      span: Span.new(:fpt, 2_000, byte_size(raw))
    }
  end

  defp slice(raw, span, source_span) do
    binary_part(raw, span.offset - source_span.offset, span.length)
  end
end
