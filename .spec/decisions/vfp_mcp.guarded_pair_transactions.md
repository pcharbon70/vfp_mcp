---
id: vfp_mcp.guarded_pair_transactions
status: accepted
date: 2026-09-09
affects:
  - vfp_mcp.mutation
  - vfp_mcp.acceptance
---

# Serialize

## Context

An SCX/SCT form is a two-file source unit. Updating a DBF memo pointer before
its FPT block is durable can corrupt the pair, while concurrent or stale edits
can overwrite an unrelated change. Windows does not provide one ordinary atomic
replacement operation for both files.

## Decision

The server starts read-only and routes every enabled mutation through one
serialized writer. A mutation uses an expiring prepared plan bound to the
canonical pair identity, complete pair hash, target path, old value, and exact
edit footprint. It acquires an exclusive pair lock, reparses fresh bytes,
creates a recoverable pair backup, appends memo data before changing DBF
pointers, validates the written pair, records a journal entry and structured
diff, and rolls back or reports a recoverable state on failure.

The ordering and recovery invariants are accepted here; the exact Windows
replacement and crash-recovery primitive remains an acceptance gate and may not
be inferred from this ADR.

## Consequences

Writes are slower and reject stale or ambiguous requests. Orphaned memo blocks
may remain after append-only edits, and only one mutation runs at a time. In
return, edits are reviewable, bounded, and recoverable without treating the
cache or Git as the source of truth.
