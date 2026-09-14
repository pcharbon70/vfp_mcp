# External VFP 6 Fixture Handoff

Use this procedure only on a workstation with a native Visual FoxPro 6 IDE. It
does not authorize access to LecoWin2, SBT, or any other application project or
data.

<!-- specled covers: vfp_mcp.acceptance.version_native_handoff vfp_mcp.acceptance.no_live_dependencies -->

## Package supplied to the operator

- The synthetic fixture instructions from `fixture-authoring-checklist.md`.
- Empty evidence JSON and Markdown templates.
- For edit acceptance only, hash-identified disposable VFP6 fixture copies.
- A manifest listing every supplied file, size, and SHA-256.

No original application source, DBC, DBF data table, connection, executable,
deployment, backup, credential, customer information, or external class library
may be included.

## Operator procedure

1. Verify the supplied manifest before opening the IDE.
2. Create a new empty directory used only for `vfp_mcp` synthetic artifacts.
3. Author the requested SCX/SCT and VCX/VCT pairs independently in VFP6, or copy
   only the supplied disposable pair for an edit-acceptance scenario.
4. Use VFP base classes and the exact synthetic content in the fixture checklist.
5. Do not open an application project, database, table, connection, executable,
   original source tree, or network share.
6. For edit scenarios, perform the exact open, inspect, save, close, reopen, and
   compile actions and record every outcome and anomaly.
7. Close VFP6 before computing result hashes.
8. Complete the JSON record and Markdown signoff without changing their evidence
   ID or pair hashes.
9. Return only the complete source/result pairs, JSON records, Markdown signoffs,
   and a final manifest.

## Local receipt

Place returned files in a new isolated package beneath
`.vfp_mcp/fixture-drop/vfp6`. Do not open or execute them. Validate the manifest,
JSON, signoff, pair completeness, content inventory, dependencies, and hashes.
Any mismatch or unexplained content rejects the entire returned package.
