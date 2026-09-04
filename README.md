# VFP MCP

An Elixir/OTP MCP server for understanding and safely editing Visual FoxPro 6
and Visual FoxPro 9 form and class-library source pairs.

The repository currently contains architecture and component design documents,
format research, PowerShell format proofs of concept, and a synthetic fixture
intake workflow. The MCP server is being built incrementally: read-only parsing
first, followed by guarded SCX property and method edits after VFP 6/9
acceptance testing.

## Development

The project requires an Elixir/Erlang toolchain:

```text
mix deps.get
mix test
```

The MCP SDK is `ex_mcp` 1.0.0-rc.8, isolated behind the application server
boundary. The initial transport is stdio.

## Fixtures

Create synthetic VFP 6 and VFP 9 pairs using
`docs/testing/fixture-authoring-checklist.md`. Place closed pairs in the ignored
`.vfp_mcp/fixture-drop/vfp6` or `vfp9` directory, validate them with
`scripts/intake-fixtures.ps1`, and promote reviewed pairs into `test/fixtures`.

Never use raw application-derived files as committed fixtures.
