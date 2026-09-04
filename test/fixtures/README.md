# Synthetic VFP fixtures

Approved fixture pairs belong under `vfp6/` and `vfp9/`. The two directories
must contain independently authored VFP 6 and VFP 9 pairs with matching
semantics, not copied application source.

Use this workflow:

1. Author and save the closed pairs in native VFP 6 and VFP 9.
2. Put them in `.vfp_mcp/fixture-drop/vfp6/` and
   `.vfp_mcp/fixture-drop/vfp9/`.
3. Run `powershell -File scripts/intake-fixtures.ps1` for a read-only check.
4. Review the manifest and the human checklist in
   `docs/testing/fixture-authoring-checklist.md`.
5. Run the same script with `-Promote` only after review.

The intake rejects data bindings, database commands, external paths, and
external class locations. It records hashes and format metadata for every pair.
