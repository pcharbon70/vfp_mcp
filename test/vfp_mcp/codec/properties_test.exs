defmodule VfpMcp.Codec.PropertiesTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.{Encoding, Properties}
  alias VfpMcp.Codec.Encoding.TextValue
  alias VfpMcp.Source.Span

  # specled covers:
  # - vfp_mcp.codec.property_edit_scope
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning

  test "parses supported literals without normalizing spelling or separators" do
    raw =
      IO.iodata_to_binary([
        "Caption  =  \"Caf",
        <<0xE9>>,
        "\"\r\n",
        "Enabled=.T.\r\n",
        "Count = -12\r\n",
        "Ratio = 12.50\r\n",
        "Missing = .NULL.\r\n",
        "Start = {^2026-09-14}\r\n",
        "At = {^2026-09-14 06:42:41}\r\n"
      ])

    {memo, findings} = Properties.parse(view(raw), :windows_1252)

    assert findings == []
    assert memo.raw_bytes == raw
    assert memo.line_ending == :crlf
    assert memo.edit_eligibility == :eligible

    assert Enum.map(memo.entries, &{&1.name, &1.literal_kind, &1.value}) == [
             {"Caption", :string, "Café"},
             {"Enabled", :boolean, true},
             {"Count", :integer, -12},
             {"Ratio", :decimal, {:decimal, "12.50"}},
             {"Missing", :null, nil},
             {"Start", :date, {:date, ~D[2026-09-14]}},
             {"At", :datetime, {:datetime, ~N[2026-09-14 06:42:41]}}
           ]

    [caption, enabled | _rest] = memo.entries
    assert caption.separators == %{before_equals: "  ", equals: "=", after_equals: "  "}
    assert caption.raw_literal == <<?\", "Caf", 0xE9, ?\">>
    assert slice(raw, caption.literal_span, memo.span) == caption.raw_literal
    assert caption.literal_span.length == 6
    assert caption.literal_text_span.length == 7

    {enabled_offset, _length} = :binary.match(raw, "Enabled")
    assert enabled.byte_span.offset == memo.span.offset + enabled_offset
    assert enabled.text_span.offset == enabled_offset + 1
  end

  test "preserves comments, blank lines, expressions, continuations, and duplicate names" do
    raw =
      "\nCaption = \"One\"\ncaption = \"Two\"\nCalc = =1 + 2\n" <>
        "* PROCEDURE Fake\ncontinued = foo ;\n  still_opaque\n"

    {memo, findings} = Properties.parse(view(raw), :windows_1252)

    assert memo.raw_bytes == raw
    assert IO.iodata_to_binary(Enum.map(memo.entries, & &1.raw_bytes)) == raw
    assert memo.line_ending == :lf

    assert Enum.map(memo.entries, & &1.kind) == [
             :blank,
             :assignment,
             :assignment,
             :assignment,
             :comment,
             :continuation,
             :unsupported
           ]

    [first, second] = Enum.filter(memo.entries, &(&1.canonical_name == "caption"))
    assert first.name == "Caption"
    assert second.name == "caption"
    assert first.edit_eligibility == {:blocked, [:property_duplicate_assignment]}
    assert second.edit_eligibility == {:blocked, [:property_duplicate_assignment]}

    calc = Enum.find(memo.entries, &(&1.canonical_name == "calc"))
    assert calc.raw_literal == "=1 + 2"
    assert calc.literal_kind == :unsupported
    assert calc.edit_eligibility == {:blocked, [:property_unsupported_literal]}

    codes = Enum.map(findings, & &1.code)
    assert :property_duplicate_assignment in codes
    assert :property_unsupported_literal in codes
    assert :property_continuation in codes
    assert :property_unsupported_line in codes
    assert match?({:blocked, _codes}, memo.edit_eligibility)
  end

  test "malformed strings block only the parsed assignment and retain exact bytes" do
    raw = "Broken = \"unterminated\r\nSafe = 42\r\n"
    {memo, findings} = Properties.parse(view(raw), :windows_1252)

    assert Enum.map(findings, & &1.code) == [:property_malformed_string]
    [broken, safe] = memo.entries
    assert broken.edit_eligibility == {:blocked, [:property_malformed_string]}
    assert safe.edit_eligibility == :eligible
    assert safe.value == 42
    assert memo.raw_bytes == raw
  end

  test "empty memos produce an empty, lossless index" do
    {memo, findings} = Properties.parse(view(<<>>), :windows_1252)
    assert findings == []
    assert memo.entries == []
    assert memo.raw_bytes == <<>>
    assert memo.line_ending == :none
  end

  defp view(raw) do
    {:ok, text} = Encoding.decode(raw, :windows_1252)

    %TextValue{
      source: :memo,
      record_index: 7,
      field: "PROPERTIES",
      block_type: 1,
      raw_bytes: raw,
      text: text,
      span: Span.new(:fpt, 1_000, byte_size(raw))
    }
  end

  defp slice(raw, span, source_span) do
    binary_part(raw, span.offset - source_span.offset, span.length)
  end
end
