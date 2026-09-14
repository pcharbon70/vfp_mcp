# VFP 6 and VFP 9 Fixture Authoring Checklist

<!--
specled covers:
- vfp_mcp.boundary.fixture_intake
- vfp_mcp.acceptance.synthetic_native_fixtures
- vfp_mcp.acceptance.no_live_dependencies
- vfp_mcp.acceptance.fixture_review
- vfp_mcp.acceptance.native_edit_matrix
- vfp_mcp.acceptance.version_compatibility
- vfp_mcp.acceptance.admit_fixture
- vfp_mcp.acceptance.accept_edit_class
-->

**Purpose:** Create synthetic, commit-safe SCX/SCT and VCX/VCT pairs for codec,
edit, recovery, and manual acceptance testing.

Use the admission states and evidence bundle defined in
[`fixture-lifecycle-and-evidence.md`](fixture-lifecycle-and-evidence.md). VFP6
operators also follow [`vfp6-handoff.md`](vfp6-handoff.md); local VFP9 operators
follow [`vfp9-native-workflow.md`](vfp9-native-workflow.md).

Create the VFP 6 suite in Visual FoxPro 6 and the VFP 9 suite independently in
Visual FoxPro 9. Do not derive captions, names, methods, paths, classes, or data
bindings from an existing application.

## General rules

- Work in a new empty directory created solely for `vfp_mcp` fixtures.
- Do not add a real DBC, DBF, connection, executable, or production path.
- Use only VFP base classes unless the checklist explicitly requests a synthetic
  VCX class.
- Use the exact ASCII object names below so cross-version comparisons are clear.
- Save and close VFP before providing a pair for automated inspection.
- Do not compile an EXE or include generated application data.

## Fixture 1: `basic_form`

Create a form named `frmBasic` and save it as `basic_form.scx`.

Form properties:

| Property | Value |
|---|---|
| Caption | `VFP MCP Basic Fixture` |
| Width | `420` |
| Height | `240` |
| AutoCenter | `.T.` |

Add these base-class controls:

| Base class | Name | Key properties |
|---|---|---|
| Label | `lblGreeting` | Caption=`Café déjà vu`; Left=20; Top=20 |
| TextBox | `txtName` | Left=20; Top=50; Width=180; Value=`Sample` |
| CheckBox | `chkEnabled` | Caption=`Enabled`; Left=20; Top=85; Value=.T. |
| CommandButton | `cmdApply` | Caption=`Apply`; Left=20; Top=125 |
| CommandButton | `cmdClose` | Caption=`Close`; Left=110; Top=125 |

Add synthetic method source:

```foxpro
PROCEDURE cmdApply.Click
THISFORM.Caption = "Applied"
ENDPROC
```

```foxpro
PROCEDURE cmdClose.Click
THISFORM.Release()
ENDPROC
```

Do not add `ControlSource`, `RecordSource`, or a data-environment cursor.

## Fixture 2: `nested_form`

Create `frmNested` and save it as `nested_form.scx`.

Add this hierarchy using base classes:

```text
frmNested
  cntOuter (Container)
    lblInside (Label)
    txtInside (TextBox)
  pgfMain (PageFrame)
    Page1
      cmdPageOne (CommandButton)
    Page2
      chkPageTwo (CheckBox)
```

Give every control distinct `Top`, `Left`, `Width`, and `Height` values. Place
`lblInside` and `txtInside` close together without overlap so layout rendering
has an obvious expected result. Add one short `Click` method to `cmdPageOne`.

## Fixture 3: `grid_form`

Create `frmGrid` and save it as `grid_form.scx`.

- Add a base-class grid named `grdItems`.
- Set an explicit `ColumnCount` of 2.
- Preserve the VFP-authored column, header, and contained-control records.
- Give the two headers synthetic captions `Code` and `Description`.
- Do not assign a `RecordSource` or `ControlSource`.
- Add one harmless grid event method that changes only a form caption.

## Fixture 4: `fixture_classes`

Create `fixture_classes.vcx` with this synthetic inheritance chain:

```text
McpBaseButton      -> CommandButton
McpConfirmButton   -> McpBaseButton
```

Set a distinct caption or color property on `McpBaseButton`. Add a harmless
`Click` method to `McpConfirmButton`, such as assigning a fixed string to its
own `ToolTipText`. Create `class_form.scx` containing one instance of
`McpConfirmButton` and no other custom dependency.

Keep `fixture_classes.vcx/.vct` beside `class_form.scx/.sct` so `CLASSLOC`
resolution stays inside the fixture directory.

## Optional opaque-memo fixture

Create this only if it can be done without external application dependencies or
licensed third-party controls. Add a standard VFP control that causes VFP to
author non-empty OLE/OLE2 memo content, save it as `opaque_form.scx`, and do not
embed personal, customer, or proprietary content.

If that cannot be guaranteed, omit this fixture initially. Opaque memo
preservation can be tested later with a purpose-built synthetic artifact.

## Delivery layout

Provide the closed pairs in separate version-native directories:

```text
fixture-drop/
  vfp6/
    basic_form.scx
    basic_form.sct
    nested_form.scx
    nested_form.sct
    grid_form.scx
    grid_form.sct
    fixture_classes.vcx
    fixture_classes.vct
    class_form.scx
    class_form.sct
  vfp9/
    ...same logical fixture set, authored independently in VFP 9...
```

Before committing them, automated intake will inventory all records, memo
fields, bindings, code, class locations, and strings. A human then confirms
that the files contain only the synthetic content described here. Promotion is
allowed only when both reviews refer to the same member and pair hashes and the
admission manifest records both evidence IDs.

## Manual acceptance matrix

For every guarded edit type, test the native version first:

1. Copy the fixture pair to a disposable working directory.
2. Apply the edit with an expected pair hash.
3. Reparse and validate it through `vfp_mcp`.
4. Open it in the originating VFP version's designer.
5. Confirm the edited property or named event and all unchanged siblings.
6. Save, close, reopen, and compile the form.
7. Run only fixtures with no external data or connection references.
8. Record pass/fail and any VFP-generated byte changes.

Cross-open VFP 6-authored fixtures in VFP 9 as an additional compatibility
check. Do not make VFP 6 acceptance of VFP 9-only features a release gate.
