# Local VFP 9 Native Workflow

Use the installed VFP9 IDE manually and only with dependency-free synthetic
fixtures owned by this repository.

<!-- specled covers: vfp_mcp.acceptance.version_native_handoff vfp_mcp.acceptance.no_live_dependencies -->

1. Create a new empty directory outside all application roots.
2. Follow `fixture-authoring-checklist.md` exactly when authoring fixtures.
3. Never open an application project, DBC, data table, connection, executable,
   original source tree, deployment, or backup.
4. For edit acceptance, copy an admitted synthetic pair to an approved disposable
   root before using the codec result.
5. Perform the required human actions and record observations in the JSON record.
6. Close VFP9 before hashing or packaging files.
7. Complete the Markdown signoff against the exact JSON evidence and pair hashes.
8. Place new fixture candidates in `.vfp_mcp/fixture-drop/vfp9` for quarantine,
   automated inventory, and a separate human promotion review.

No test or automation may control the IDE or represent these steps as completed.
