# Phase 3 Semantic Codec Suite

<!--
specled covers:
- vfp_mcp.acceptance.codec_evidence
- vfp_mcp.acceptance.quality_gate
- vfp_mcp.acceptance.deterministic_test_vectors
- vfp_mcp.acceptance.run_phase3_semantic_suite
- vfp_mcp.codec.property_edit_scope
- vfp_mcp.codec.method_edit_scope
- vfp_mcp.codec.semantic_document
- vfp_mcp.codec.hierarchy_integrity
- vfp_mcp.codec.raw_fidelity
- vfp_mcp.codec.pure_planning
- vfp_mcp.package.phase_quality_gates
- vfp_mcp.package.run_phase_gate
-->

Run the complete Phase 3 gate from the repository root:

```powershell
mix phase3
```

The alias checks formatting, compiles with warnings as errors, runs the complete
test suite with seed `16180`, and validates the SpecLed workspace strictly.

All Phase 3 automated inputs are generated DBF/FPT bytes. The suite does not
require, discover, open, copy, compile, execute, or mutate LecoWin2, SBT, a VFP
IDE, application data, or any external project root.

The integration vectors cover generated SCX/SCT and VCX/VCT documents with
bookends, data-environment records, nested containers, grids, columns,
properties, methods, reserved data, and opaque memo bytes. Invalid vectors
cover hierarchy and path ambiguity, depth bounds, property ambiguity, and
malformed method bookends while proving that original bytes remain available.

The repeatability checks compare complete parse results and content-safe
semantic summaries across concurrent callers with different process-local
locale labels. The no-hidden-effects check proves that parsing ignores optional
identity paths, creates no files, emits no standard output or error, starts no
processes, and returns no process, port, reference, function, or protocol value.
