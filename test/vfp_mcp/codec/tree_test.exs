defmodule VfpMcp.Codec.TreeTest do
  use ExUnit.Case, async: true

  alias VfpMcp.Codec.Tree
  alias VfpMcp.{Limits, SemanticValue, SourceObject}
  alias VfpMcp.Source.Span

  # specled covers:
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.full_path_identity
  # - vfp_mcp.read.validation_findings

  test "resolves nested form and grid containment independently of record order" do
    objects = [
      object(5, "Header One", "Column/One", "header"),
      object(0, "Frm/Main", "", "form"),
      object(3, "Grid One", "Page One", "grid"),
      object(1, "Pages", "Frm/Main", "pageframe"),
      object(4, "Column/One", "Grid One", "column"),
      object(2, "Page One", "Pages", "page")
    ]

    assert {:ok, resolved, tree, path_index, []} = Tree.build(objects, Limits.new!())

    assert paths_by_record(resolved) == %{
             0 => "Frm%2FMain",
             1 => "Frm%2FMain/Pages",
             2 => "Frm%2FMain/Pages/Page%20One",
             3 => "Frm%2FMain/Pages/Page%20One/Grid%20One",
             4 => "Frm%2FMain/Pages/Page%20One/Grid%20One/Column%2FOne",
             5 => "Frm%2FMain/Pages/Page%20One/Grid%20One/Column%2FOne/Header%20One"
           }

    assert tree.roots == [0]
    assert tree.children == %{0 => [1], 1 => [2], 2 => [3], 3 => [4], 4 => [5]}

    lookup = "frm%2Fmain/pages/page%20one/grid%20one/column%2fone/header%20one"
    assert {:ok, %{record_index: 5}} = Tree.lookup(path_index, lookup)

    assert {:ok, reordered, reordered_tree, reordered_index, []} =
             Tree.build(Enum.reverse(objects), Limits.new!())

    assert paths_by_record(reordered) == paths_by_record(resolved)
    assert reordered_tree == tree
    assert reordered_index == path_index
  end

  test "supports repeated local names in different containers" do
    objects = [
      object(0, "Form", "", "form"),
      object(1, "Left", "Form", "container"),
      object(2, "Right", "Form", "container"),
      object(3, "Button", "Left", "commandbutton"),
      object(4, "Button", "Right", "commandbutton")
    ]

    assert {:ok, resolved, _tree, path_index, []} = Tree.build(objects, Limits.new!())
    assert paths_by_record(resolved)[3] == "Form/Left/Button"
    assert paths_by_record(resolved)[4] == "Form/Right/Button"
    assert map_size(path_index) == 5
  end

  test "reports missing, self, cyclic, and incompatible parent relationships" do
    objects = [
      object(0, "Form", "", "form"),
      object(1, "Missing", "NoSuchParent", "commandbutton"),
      object(2, "Self", "Self", "container"),
      object(3, "CycleA", "CycleB", "container"),
      object(4, "CycleB", "CycleA", "container"),
      object(5, "Leaf", "Form", "label"),
      object(6, "Child", "Leaf", "commandbutton")
    ]

    assert {:ok, resolved, _tree, path_index, findings} = Tree.build(objects, Limits.new!())
    codes = Enum.map(findings, & &1.code)

    assert :hierarchy_parent_missing in codes
    assert :hierarchy_self_parent in codes
    assert :hierarchy_cycle in codes
    assert :hierarchy_incompatible_parent in codes
    assert Enum.all?(Enum.filter(resolved, &(&1.record_index in 1..4)), &is_nil(&1.path))
    assert Enum.find(resolved, &(&1.record_index == 6)).path == nil
    assert Map.keys(path_index) == ["form", "form/leaf"]
  end

  test "bounds depth and omits over-depth descendants from lookup" do
    objects = [
      object(0, "Root", "", "form"),
      object(1, "One", "Root", "container"),
      object(2, "Two", "One", "container"),
      object(3, "Three", "Two", "commandbutton")
    ]

    limits = Limits.new!(hierarchy_depth: 2)
    assert {:ok, resolved, _tree, path_index, findings} = Tree.build(objects, limits)
    assert Enum.any?(findings, &(&1.code == :limit_hierarchy_depth_exceeded))
    assert Enum.find(resolved, &(&1.record_index == 3)).path == nil
    refute Map.has_key?(path_index, "root/one/two/three")
  end

  test "an object with no usable name remains inspectable but unaddressable" do
    objects = [object(0, "", "", "form")]
    assert {:ok, [object], %{roots: []}, %{}, [finding]} = Tree.build(objects, Limits.new!())
    assert object.path == nil
    assert finding.code == :hierarchy_object_name_missing
  end

  test "duplicate and case-colliding sibling paths never enter the target index" do
    objects = [
      object(0, "Form", "", "form"),
      object(1, "Same", "Form", "commandbutton"),
      object(2, "Same", "Form", "commandbutton"),
      object(3, "Mixed", "Form", "commandbutton"),
      object(4, "mixed", "Form", "commandbutton")
    ]

    assert {:ok, resolved, _tree, path_index, findings} = Tree.build(objects, Limits.new!())
    codes = Enum.map(findings, & &1.code)
    assert :hierarchy_duplicate_sibling in codes
    assert :hierarchy_path_canonicalization_collision in codes
    refute Map.has_key?(path_index, "form/same")
    refute Map.has_key?(path_index, "form/mixed")

    for object <- Enum.filter(resolved, &(&1.record_index in 1..4)) do
      assert object.edit_eligibility == {:blocked, [:hierarchy_path_ambiguous]}
    end
  end

  defp object(record_index, name, parent, baseclass) do
    %SourceObject{
      semantic_index: record_index,
      record_index: record_index,
      category: :object,
      active?: true,
      identity_fields: %{
        objname: value(record_index, "OBJNAME", name),
        parent: value(record_index, "PARENT", parent),
        baseclass: value(record_index, "BASECLASS", baseclass)
      }
    }
  end

  defp value(record_index, field, value) do
    %SemanticValue{
      field: field,
      field_index: 0,
      value: value,
      raw_bytes: value,
      span: Span.new(:fpt, record_index * 100, byte_size(value))
    }
  end

  defp paths_by_record(objects), do: Map.new(objects, &{&1.record_index, &1.path})
end
