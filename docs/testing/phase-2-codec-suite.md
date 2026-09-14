# Phase 2 Physical Codec Suite

<!--
specled covers:
- vfp_mcp.acceptance.codec_evidence
- vfp_mcp.acceptance.quality_gate
- vfp_mcp.acceptance.run_phase2_codec_suite
-->

Run the complete Phase 2 gate from the repository root:

```powershell
mix phase2
```

The alias checks formatting, compiles with warnings as errors, runs all unit,
property, malformed-input, safety, protocol, and integration tests with seed
`24680`, and strictly validates the SpecLed workspace. StreamData reports the
seed and minimized input if a generated case fails.

The physical codec uses only immutable caller-supplied binaries. The gate does
not configure an external VFP root, open Visual FoxPro, access either original
application tree, perform filesystem reads through the codec, or emit MCP
values.

Focused evidence is located at:

- `test/vfp_mcp/codec/dbf_test.exs`
- `test/vfp_mcp/codec/fpt_test.exs`
- `test/vfp_mcp/codec/encoding_test.exs`
- `test/vfp_mcp/codec/physical_codec_test.exs`
- `test/integration/phase_2_physical_codec_test.exs`
