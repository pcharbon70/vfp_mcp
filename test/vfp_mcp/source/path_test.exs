defmodule VfpMcp.Source.PathTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Source.Path

  # specled covers:
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.full_path_identity

  test "segments with separators, percent, spaces, extended text, and case round-trip" do
    segments = ["Frm Main", "Grid/One", "Col%Mix", "Café"]
    path = Path.build(segments)

    assert path == "Frm%20Main/Grid%2FOne/Col%25Mix/Caf%C3%A9"
    assert Path.parse(path) == {:ok, segments}

    assert Path.canonicalize(path) ==
             {:ok, "frm%20main/grid%2Fone/col%25mix/caf%C3%A9"}
  end

  test "invalid path syntax is rejected rather than partially decoded" do
    assert Path.parse("") == {:error, :empty_path}
    assert Path.parse("root//child") == {:error, :empty_segment}
    assert Path.parse("root/%") == {:error, :invalid_percent_escape}
    assert Path.parse("root/%GG") == {:error, :invalid_percent_escape}
    assert Path.parse("root/%FF") == {:error, :invalid_utf8}
  end
end
