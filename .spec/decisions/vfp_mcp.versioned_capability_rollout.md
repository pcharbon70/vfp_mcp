---
id: vfp_mcp.versioned_capability_rollout
status: accepted
date: 2026-09-09
affects:
  - vfp_mcp.package
  - vfp_mcp.project_boundary
  - vfp_mcp.protocol
  - vfp_mcp.mutation
  - vfp_mcp.acceptance
---

# Gate

## Context

VFP 6 and VFP 9 source pairs share a broad storage model but may differ in
encoding, timestamps, designer metadata, and accepted record conventions.
Reading existing records is lower risk than rewriting memos, and structural
record edits carry substantially more uncertainty than property or method
changes.

## Decision

One server process targets either VFP 6 or VFP 9. Delivery proceeds through
acceptance-gated capabilities: first the codec and native fixtures, then a
read-only MCP surface, then guarded edits to existing SCX properties and named
method blocks, and only later structural editing. VCX/VCT is read-only in the
initial write milestone. Mixed-version sources may be inspected with findings, but
incompatible writes are rejected.

## Consequences

Users must launch separate processes for different compatibility targets.
Useful mutations arrive later, but no write capability ships on the strength of
self-parsing alone. Each native VFP version must accept its own edited synthetic
fixtures before that edit class is enabled.
