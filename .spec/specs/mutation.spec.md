# Guarded Mutation Pipeline

The planned write contract for accepted, narrowly scoped changes to existing
SCX/SCT form pairs.

## Intent

Make every write explicit, fresh, bounded, serialized, recoverable, validated,
and reviewable while deferring unsupported versions, sources, and structural
operations.

```spec-meta
id: vfp_mcp.mutation
kind: service
status: planned
summary: Prepared and serialized two-file transactions for accepted SCX edits.
surface:
  - docs/architecture.md
  - docs/components.md
  - docs/research/progress-to-date.md
decisions:
  - vfp_mcp.custom_vfp_codec
  - vfp_mcp.versioned_capability_rollout
  - vfp_mcp.guarded_pair_transactions
```

## Requirements

```spec-requirements
- id: vfp_mcp.mutation.explicit_enablement
  statement: Mutations shall be unavailable unless the user explicitly enables write mode and the requested edit class has passed all applicable acceptance gates.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.scx_only
  statement: The first write milestone shall modify only existing properties and named method blocks in SCX/SCT form pairs and shall keep VCX/VCT and structural record edits read-only.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.prepared_plan
  statement: A write shall require an unexpired prepared plan bound to the canonical pair identity, complete pair hash, compatibility target, control full path, expected old value, and exact byte footprint.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.preconditions
  statement: Before writing, the server shall verify root confinement, pair completeness, source version, supported encoding, pair hash, target uniqueness, expected value or match count, exclusive access, and allowed record and field types.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.fresh_authority
  statement: The writer shall read and parse both source files after acquiring the pair lock and shall never mutate from cached or previously prepared bytes.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.restricted_footprint
  statement: A property edit shall alter only targeted property lines, and a method edit shall alter only the named procedure block or an exact guarded match while preserving every unrelated record, memo, and opaque field.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.append_memo
  statement: Replacement memo content shall be appended at a valid aligned block using the replaced block type, with the next-free pointer updated consistently and the old block left unreachable rather than overwritten in place.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.method_objcode
  statement: Every method-source mutation shall clear the affected record OBJCODE pointer so stale compiled code cannot remain authoritative.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.timestamp_gate
  statement: The writer shall preserve TIMESTAMP bytes until VFP 6 and VFP 9 timestamp encoding and rewrite behavior have been established by native before-and-after acceptance evidence.
  priority: must
  stability: evolving

- id: vfp_mcp.mutation.single_writer
  statement: One supervised writer shall serialize all mutations and hold an exclusive lock over both members of the selected source pair for the transaction.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.recoverable_backup
  statement: Before changing either source file, the writer shall create and verify a complete pair backup under .vfp_mcp/backups and retain the latest 20 backups per form by default.
  priority: must
  stability: evolving

- id: vfp_mcp.mutation.commit_order
  statement: New memo bytes shall be made durable before any DBF pointer can reference them, and the accepted Windows replacement protocol shall never expose a new pointer to an absent block.
  priority: must
  stability: evolving

- id: vfp_mcp.mutation.post_validation
  statement: After replacement, the writer shall re-read and validate the pair, verify the requested semantic postcondition and restricted footprint, and invalidate or refresh cache entries only after success.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.audit_journal
  statement: Each attempt shall produce a metadata journal entry and successful edits shall additionally produce a structured semantic diff without recording full source bodies or secrets.
  priority: must
  stability: stable

- id: vfp_mcp.mutation.rollback
  statement: Any failed post-write check shall restore the previous complete pair when safe or leave a precisely identified recoverable state with the verified backup untouched.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.mutation.prepare_then_apply
  given:
    - write mode and the requested SCX edit class are enabled
    - the current pair is valid and exclusively available
  when:
    - a matching unexpired prepared plan is applied
  then:
    - only the planned footprint changes and the response includes the new pair identity and structured diff
  covers:
    - vfp_mcp.mutation.explicit_enablement
    - vfp_mcp.mutation.prepared_plan
    - vfp_mcp.mutation.preconditions
    - vfp_mcp.mutation.restricted_footprint
    - vfp_mcp.mutation.post_validation
    - vfp_mcp.mutation.audit_journal

- id: vfp_mcp.mutation.reject_stale_plan
  given:
    - a prepared plan references an earlier complete pair hash
  when:
    - either member changed before apply
  then:
    - the write is rejected before backup or source mutation
  covers:
    - vfp_mcp.mutation.prepared_plan
    - vfp_mcp.mutation.preconditions
    - vfp_mcp.mutation.fresh_authority

- id: vfp_mcp.mutation.named_method_update
  given:
    - an SCX object has multiple method blocks and compiled OBJCODE
  when:
    - an accepted edit updates one named method
  then:
    - a new memo block contains the targeted source change, sibling methods remain byte-faithful, and the affected OBJCODE pointer is zero
  covers:
    - vfp_mcp.mutation.scx_only
    - vfp_mcp.mutation.restricted_footprint
    - vfp_mcp.mutation.append_memo
    - vfp_mcp.mutation.method_objcode
    - vfp_mcp.mutation.timestamp_gate

- id: vfp_mcp.mutation.reject_unsupported_write
  given:
    - a request targets VCX/VCT, structural records, or an edit class without native acceptance
  when:
    - the request is prepared or applied
  then:
    - it is rejected without creating source bytes
  covers:
    - vfp_mcp.mutation.explicit_enablement
    - vfp_mcp.mutation.scx_only

- id: vfp_mcp.mutation.recover_interrupted_pair
  given:
    - a verified pair backup exists and a failure occurs during replacement or post-validation
  when:
    - the writer handles the failure
  then:
    - no DBF pointer references an absent memo block and the previous pair is restored or explicitly recoverable
  covers:
    - vfp_mcp.mutation.single_writer
    - vfp_mcp.mutation.recoverable_backup
    - vfp_mcp.mutation.commit_order
    - vfp_mcp.mutation.rollback
```

## Verification

```spec-verification
- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.mutation.explicit_enablement
    - vfp_mcp.mutation.prepared_plan
    - vfp_mcp.mutation.preconditions
    - vfp_mcp.mutation.fresh_authority
    - vfp_mcp.mutation.single_writer
    - vfp_mcp.mutation.recoverable_backup
    - vfp_mcp.mutation.commit_order
    - vfp_mcp.mutation.post_validation
    - vfp_mcp.mutation.audit_journal
    - vfp_mcp.mutation.rollback
    - vfp_mcp.mutation.prepare_then_apply
    - vfp_mcp.mutation.reject_stale_plan
    - vfp_mcp.mutation.recover_interrupted_pair

- kind: guide_file
  target: docs/components.md
  covers:
    - vfp_mcp.mutation.scx_only
    - vfp_mcp.mutation.restricted_footprint
    - vfp_mcp.mutation.append_memo
    - vfp_mcp.mutation.method_objcode
    - vfp_mcp.mutation.named_method_update
    - vfp_mcp.mutation.reject_unsupported_write

- kind: guide_file
  target: docs/research/progress-to-date.md
  covers:
    - vfp_mcp.mutation.timestamp_gate
```
