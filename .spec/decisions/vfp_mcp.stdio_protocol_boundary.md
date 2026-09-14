---
id: vfp_mcp.stdio_protocol_boundary
status: accepted
date: 2026-09-09
affects:
  - vfp_mcp.package
  - vfp_mcp.protocol
---

# Use

## Context

The server needs a Windows-friendly MCP integration while the storage and
domain layers are still evolving. Coupling the codec or use cases directly to
a young MCP SDK would make protocol churn affect the safety-critical core.

## Decision

The first supported transport is stdio, implemented with the pinned `ex_mcp`
SDK behind `VfpMcp.Server` and protocol adapter modules. Domain operations use
SDK-neutral inputs, outputs, and errors. Standard output is reserved for MCP
frames; diagnostics use standard error. Streamable HTTP, resources, prompts,
and remote deployment are deferred.

## Consequences

Initial deployment is local and single-session rather than a shared service.
The adapter must translate tool schemas, annotations, results, and domain
errors without leaking SDK types into the codec or query layers. A later SDK or
transport change stays localized to the protocol boundary.
