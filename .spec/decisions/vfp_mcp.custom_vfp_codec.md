---
id: vfp_mcp.custom_vfp_codec
status: accepted
date: 2026-09-09
affects:
  - vfp_mcp.codec
  - vfp_mcp.read_service
  - vfp_mcp.mutation
---

# Own

## Context

SCX/VCX files are DBF containers whose memo fields point into companion FPT
files. The format mixes little-endian DBF values with big-endian FPT values,
uses binary memo pointers, contains opaque and designer-owned fields, and must
preserve bytes outside an explicitly requested edit. Surveyed Elixir DBF
libraries do not implement the required VFP memo semantics or safe writes.

## Decision

The project owns a small, SDK-independent DBF/FPT codec implemented with pure
binary transformations. It parses physical storage into a semantic source
document while retaining raw record, memo, reserved, deleted, and opaque bytes.
Edit planning remains pure; stateful components own only discovery, caching,
locking, backup, journaling, and disk I/O.

Text is UTF-8 inside the application and is decoded or encoded only at the
source boundary. Writes are allowed only when the source code page is supported
and the round trip is lossless.

The physical stage validates the complete DBF schema before slicing records,
then resolves little-endian memo pointers against big-endian FPT allocation
metadata. Invalid or overlapping blocks retain physical bytes but do not expose
payloads as valid through memo references. Initial text support recognizes DBF
driver IDs `0x03` and `0x57` as Windows-1252; unsupported metadata and undefined
bytes remain raw and block mutation. Evidence summaries contain canonical
offset, length, scalar, and SHA-256 data rather than source bodies.

The pure boundary accepts an immutable `PairSnapshot` containing both members,
their individual identities, and a complete pair hash. Semantic documents and
edit plans retain explicit byte spans and memo references. Stable findings
separate unreadable input, mutation-blocking ambiguity, preserved unknown
content, and informational compatibility notes. All parsers and traversals use
shared configurable limits before allocation or descent.

## Consequences

The team owns format correctness, malformed-input handling, and byte-level test
coverage instead of delegating them to a library. In return, MCP SDK changes do
not affect storage semantics, and planned mutations can prove that unrelated
bytes remain unchanged.
