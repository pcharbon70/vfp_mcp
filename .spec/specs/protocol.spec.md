# MCP Protocol Boundary

The planned local MCP transport, adapter responsibilities, startup contract,
and initial read-only tool surface.

## Intent

Expose domain behavior through a small stdio boundary while keeping the codec,
queries, and mutation plans independent of the selected MCP SDK.

```spec-meta
id: vfp_mcp.protocol
kind: adapter
status: planned
summary: Stdio MCP adapter with bounded schemas, structured results, and domain-neutral internals.
surface:
  - mix.exs
  - docs/contracts/physical-codec.md
  - lib/vfp_mcp/codec.ex
  - lib/vfp_mcp/codec/semantic.ex
  - test/vfp_mcp/codec/semantic_test.exs
  - test/integration/phase_2_physical_codec_test.exs
  - test/integration/phase_3_semantic_codec_test.exs
  - docs/architecture.md
  - docs/components.md
decisions:
  - vfp_mcp.stdio_protocol_boundary
  - vfp_mcp.versioned_capability_rollout
```

## Requirements

```spec-requirements
- id: vfp_mcp.protocol.stdio_transport
  statement: The initial server shall support local stdio transport only and shall reserve standard output exclusively for MCP protocol frames.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.diagnostic_stream
  statement: Startup diagnostics, warnings, and operational logs shall be written to standard error and shall redact sensitive source text from arguments and journal-facing output.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.sdk_boundary
  statement: ex_mcp types and callbacks shall remain inside the server and protocol adapter so domain, codec, acceptance-evidence, and test-support modules accept and return SDK-neutral values.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.startup_configuration
  statement: Startup shall require an explicit project root and VFP version, shall default writes to disabled, and shall fail before opening sources when configuration is invalid.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.initial_read_tools
  statement: The first MCP surface shall provide list_sources, get_form_overview, get_control_tree, get_control_details, list_code_locations, get_control_code, search_sources, get_dataenvironment, and validate_source.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.tool_contracts
  statement: Every tool shall validate a bounded JSON input schema and return concise text plus structured content where useful, with truthful read-only and destructive annotations.
  priority: must
  stability: evolving

- id: vfp_mcp.protocol.domain_errors
  statement: Expected domain failures shall become structured tool errors with stable categories and shall not terminate the server session or be reported as transport failures.
  priority: must
  stability: stable

- id: vfp_mcp.protocol.deferred_surfaces
  statement: Streamable HTTP, prompts, resources, subscriptions, and remote multi-session deployment shall remain outside the initial protocol surface.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.protocol.read_only_startup
  given:
    - a valid project root and one supported VFP version are supplied
    - write mode is not explicitly enabled
  when:
    - the stdio server starts
  then:
    - the read tool catalog is available and no mutating tool can change a source pair
  covers:
    - vfp_mcp.protocol.stdio_transport
    - vfp_mcp.protocol.startup_configuration
    - vfp_mcp.protocol.initial_read_tools

- id: vfp_mcp.protocol.clean_stdout
  given:
    - the server emits diagnostics while serving an MCP session
  when:
    - protocol output and logs are produced
  then:
    - standard output contains only MCP frames and diagnostics appear on standard error
  covers:
    - vfp_mcp.protocol.stdio_transport
    - vfp_mcp.protocol.diagnostic_stream

- id: vfp_mcp.protocol.recoverable_tool_error
  given:
    - a tool request passes transport decoding but violates a domain precondition
  when:
    - the request is dispatched
  then:
    - the client receives a categorized tool error and the session remains usable
  covers:
    - vfp_mcp.protocol.tool_contracts
    - vfp_mcp.protocol.domain_errors
```

## Verification

```spec-verification
- kind: source_file
  target: mix.exs
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: source_file
  target: lib/vfp_mcp/codec.ex
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: source_file
  target: lib/vfp_mcp/codec/semantic.ex
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: test_file
  target: test/vfp_mcp/codec/semantic_test.exs
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: guide_file
  target: docs/contracts/physical-codec.md
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: test_file
  target: test/integration/phase_2_physical_codec_test.exs
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: test_file
  target: test/integration/phase_3_semantic_codec_test.exs
  covers:
    - vfp_mcp.protocol.sdk_boundary

- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.protocol.stdio_transport
    - vfp_mcp.protocol.diagnostic_stream
    - vfp_mcp.protocol.startup_configuration
    - vfp_mcp.protocol.deferred_surfaces
    - vfp_mcp.protocol.clean_stdout

- kind: guide_file
  target: docs/components.md
  covers:
    - vfp_mcp.protocol.initial_read_tools
    - vfp_mcp.protocol.tool_contracts
    - vfp_mcp.protocol.domain_errors
    - vfp_mcp.protocol.read_only_startup
    - vfp_mcp.protocol.recoverable_tool_error
```
