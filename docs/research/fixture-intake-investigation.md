# Initial Fixture Intake Investigation

**Date:** August 31, 2026  
**Status:** Raw copies isolated; neither is approved as a committed or runnable fixture

## Safety boundary

This investigation followed the repository instructions in `AGENTS.md`:

- only one explicitly selected SCX/SCT pair was copied from each authorized
  read-only source tree;
- no DBF, DBC, table, connection, executable, deployment, or backup was opened;
- inspection and parsing ran only against repository-local copies;
- no original source file was modified, compiled, opened in VFP, or executed.

Raw copies are stored below `.vfp_mcp/intake/`, which is excluded by
`.gitignore`. They must not be committed or run.

## VFP 9 intake: `dialogok`

Source pair:

```text
C:\Leco\vfp\lecowin2\forms\dialogok.scx
C:\Leco\vfp\lecowin2\forms\dialogok.sct
```

Local isolated pair:

```text
.vfp_mcp\intake\vfp9\dialogok.scx
.vfp_mcp\intake\vfp9\dialogok.sct
```

Integrity:

| File | Bytes | SHA-256 |
|---|---:|---|
| SCX | 1,578 | `F35412D5F98D75D6379F9F8590B1159BB504A6C656B29A3C49D03565C5F4B5FA` |
| SCT | 3,265 | `90CC57AA7E144A45DA223003C0D1DBE548E2385CD35F1D4F118140C5B0908EDB` |

Format observations:

- DBF version byte: `0x30`.
- Code-page byte: `0x03`.
- Memo block size: 1 byte.
- Five records: opening bookend, data environment, form, command button, and
  closing bookend.
- All referenced memo blocks observed in this pair have type 1.
- Both records containing methods also contain non-empty `OBJCODE` memos.

Suitability findings:

- The data-environment record is empty and no table, DBC, cursor, or connection
  binding was found in the inspected properties or method text.
- The form and button inherit from custom classes in
  `..\visual classes\dynamic.vcx`.
- The copied pair is therefore not standalone and must not be opened or run in
  VFP without addressing that dependency.
- Its form and button method source is application-derived and must not be
  committed unchanged.

Conclusion: useful as a local, read-only parser compatibility sample. It is not
a suitable committed or runnable fixture. Prefer a newly authored VFP 9 form
using base classes for the first acceptance fixture.

## VFP 6 intake: `SYMMP3`

Source pair:

```text
C:\Leco\vfp\sbt\source\SM\SYMMP3.SCX
C:\Leco\vfp\sbt\source\SM\SYMMP3.SCT
```

Local isolated pair:

```text
.vfp_mcp\intake\vfp6\symmp3.scx
.vfp_mcp\intake\vfp6\symmp3.sct
```

Integrity:

| File | Bytes | SHA-256 |
|---|---:|---|
| SCX | 1,796 | `2563C1BB85D605A272E7E82EDD547AF374744BCF2F24DEF9D8ACDA3E433EECB3` |
| SCT | 3,292 | `0F21B4D9B3D6490AD17899E67A5A9BBB16FAFC7ED154ECEE21F67A9171CB9801` |

Format observations:

- DBF version byte: `0x30`.
- Code-page byte: `0x03`.
- Memo block size: 1 byte.
- Seven records: opening bookend, data environment, form, three command
  buttons, and closing bookend.
- All referenced memo blocks observed in this pair have type 1.
- The form and each button with method source have non-empty `OBJCODE` memos.

Suitability findings:

- The form uses VFP base classes and has no `CLASSLOC` dependency.
- The data-environment record is empty and no table, DBC, cursor, or connection
  binding was found in the inspected properties or method text.
- The form refers to an external icon using `LOCFILE`, so it is not fully
  isolated for execution.
- Its methods depend on application-specific global variables and window names.
- Captions, names, and method source are application-derived and must not be
  committed unchanged.

Conclusion: physically simpler than the VFP 9 intake and potentially useful for
local read-only codec comparison. A newly authored VFP 6 fixture is preferable
to attempting to sanitize this form in binary.

## Recommended disposition

1. Keep both raw pairs only in the ignored intake directory.
2. Do not open or run either raw pair in VFP.
3. Do not copy their source methods, captions, identifiers, or class dependencies
   into committed fixtures.
4. Create native synthetic fixture suites in VFP 6 and VFP 9 from the checklist
   in `docs/testing/fixture-authoring-checklist.md`.
5. Use raw intake pairs only for local read-only parser comparisons until they
   are deleted under an explicitly approved cleanup operation.

