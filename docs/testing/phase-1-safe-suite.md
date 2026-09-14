# Phase 1 Safe Suite

<!--
specled covers:
- vfp_mcp.acceptance.quality_gate
- vfp_mcp.acceptance.phase1_safe_foundation
- vfp_mcp.acceptance.run_phase1_safe_suite
-->

Run the complete Phase 1 gate from the repository root with no Visual FoxPro
source-root environment variable configured:

```powershell
mix phase1
```

The alias checks formatting, compiles with warnings treated as errors, runs all
unit, property, safety, protocol, and integration tests with seed `12345`, and
strictly validates the SpecLed workspace. It does not fetch dependencies, open
Visual FoxPro, use an IDE, or read any source outside the repository-owned test
inputs authorized by `VfpMcp.Development.IsolationPolicy`.

The Phase 1 integration proof is
`test/integration/phase_1_foundations_test.exs`. It uses only deterministic
in-memory pairs and structured inventories. Paths naming original-application
candidates are inert rejection inputs; the suite never opens those paths.
