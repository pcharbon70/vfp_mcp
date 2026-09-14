defmodule VfpMcp.Codec.EncodingTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.Encoding
  alias VfpMcp.Source.Span

  # specled covers:
  # - vfp_mcp.codec.lossless_encoding
  # - vfp_mcp.codec.raw_fidelity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.codec.reject_unrepresentable_text

  test "resolves supported, unsupported, and conflicting code-page metadata" do
    assert {:ok, :windows_1252, []} = Encoding.resolve(0x03)
    assert {:ok, :windows_1252, []} = Encoding.resolve(0x57, :windows_1252)

    assert {:ok, nil, [finding]} = Encoding.resolve(0x00)
    assert finding.code == :codec_unsupported_code_page
    assert finding.evidence == %{code_page: 0x00}

    assert {:ok, nil, [finding]} = Encoding.resolve(0x03, :utf8)
    assert finding.code == :codec_conflicting_code_page
  end

  test "strict Windows-1252 conversion round-trips ASCII and extended characters" do
    bytes = <<"Cafe", 0xE9, 0x20, 0x80, 0x20, 0x8C, 0x20, 0x9F>>
    text = "Cafeé € Œ Ÿ"

    assert {:ok, ^text} = Encoding.decode(bytes, :windows_1252)
    assert {:ok, ^bytes} = Encoding.encode(text, :windows_1252)
  end

  test "undefined source bytes remain raw and report their exact location" do
    span = Span.new(:fpt, 512, 3)

    assert {:error, finding} =
             Encoding.decode(<<0x41, 0x81, 0x42>>, :windows_1252, location: span)

    assert finding.code == :codec_invalid_text_bytes
    assert finding.location == %{member: :fpt, offset: 513}
    assert finding.evidence == %{byte: 0x81, relative_offset: 1}
  end

  test "unrepresentable Unicode is rejected without replacement output" do
    assert {:error, finding} = Encoding.encode("approved ✅", :windows_1252)
    assert finding.code == :codec_unrepresentable_text
    assert finding.evidence.codepoint == 0x2705
    refute match?({:ok, _bytes}, Encoding.encode("approved ✅", :windows_1252))

    assert {:error, %{code: :codec_invalid_utf8}} =
             Encoding.encode(<<0xFF>>, :windows_1252)
  end

  test "an unsupported decoder cannot fabricate text" do
    assert {:error, finding} = Encoding.decode("raw", nil)
    assert finding.code == :codec_unsupported_code_page
  end
end
