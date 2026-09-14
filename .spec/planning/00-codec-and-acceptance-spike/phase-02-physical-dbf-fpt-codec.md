---
title: "Phase 2: Physical DBF/FPT Codec"
kind: note
created: 2026-09-10
maturity: developing
tags:
  - planning
  - milestone-0
  - dbf
  - fpt
aliases: []
---

# Phase 2: Physical DBF/FPT Codec

**Description:** Implement a deterministic, loss-aware physical decoder for DBF
records and FPT memo blocks without interpreting application semantics or
performing filesystem I/O.

**Status:** In progress

**Dependencies:** Phase 1 contracts, safety limits, findings, and binary builders.

## Section 2.1 — DBF Header, Schema, and Record Decoding

**Description:** Decode DBF container structure with validated arithmetic and
retain the exact bytes and offsets needed for fidelity proofs.

### Task 2.1.1 — Decode and Validate the DBF Header

**Description:** Parse format byte, date bytes, record count, header length,
record length, code-page byte, and reserved bytes from documented offsets.

#### Subtask 2.1.1.1 — Implement Checked Header Reads

**Description:** Use explicit little-endian reads and checked range arithmetic
before taking any byte slice.

- [x] Truncated values and arithmetic overflow return stable fatal findings without raising.

#### Subtask 2.1.1.2 — Validate Container Extents

**Description:** Reconcile header length, record count, record length, terminator,
and available file bytes while retaining any permitted trailing content.

- [x] Impossible extents fail and unusual preserved trailing bytes produce a bounded finding.

- [x] Task 2.1.1 is complete with source offsets retained for every decoded header value.

### Task 2.1.2 — Decode Field Descriptors

**Description:** Parse descriptors until the validated header terminator without
assuming one fixed SCX or VCX schema.

#### Subtask 2.1.2.1 — Preserve Descriptor Metadata

**Description:** Retain raw name bytes, logical name, type, length, decimal count,
flags, reserved bytes, descriptor offset, and record-relative field offset.

- [x] Duplicate names, zero lengths, unknown types, and cumulative-width mismatches receive stable findings.

#### Subtask 2.1.2.2 — Validate Schema Bounds

**Description:** Prove that the deletion marker and all declared fields fit
inside the record length with no overflow or overlap.

- [x] No record-field slice is attempted from an invalid schema.

- [x] Task 2.1.2 is complete across reordered fields and synthetic nonstandard schemas.

### Task 2.1.3 — Decode Physical Records

**Description:** Split the record region deterministically and retain raw records,
deletion markers, raw field slices, and stable physical indices.

#### Subtask 2.1.3.1 — Decode Active and Deleted Records

**Description:** Interpret standard active and deleted markers while preserving
all record bytes regardless of semantic support.

- [x] Deleted records remain available to fidelity and validation logic and are not silently discarded.

#### Subtask 2.1.3.2 — Decode Fixed-Width Field Values Conservatively

**Description:** Expose raw bytes for every field and decode only physical scalar
types required by source containers, leaving unsupported types opaque.

- [x] Unsupported fields remain byte-faithful and cannot shift later field boundaries.

- [x] Task 2.1.3 is complete with record, marker, and field spans proven against generated vectors.

## Section 2.2 — FPT Header, Pointer, and Memo Decoding

**Description:** Resolve binary memo pointers and parse typed memo blocks using
the distinct byte orders and block rules of DBF and FPT storage.

### Task 2.2.1 — Decode the FPT Header

**Description:** Parse the next-free block and stored block size as big-endian
values while retaining the full header and reserved bytes.

#### Subtask 2.2.1.1 — Normalize the Effective Block Size

**Description:** Treat a stored size of zero as 512 bytes and accept other sizes
only when alignment and configured limits can be satisfied.

- [x] Stored and effective block sizes are both retained for evidence.

#### Subtask 2.2.1.2 — Validate Allocation Metadata

**Description:** Check the header extent, next-free location, file alignment, and
bounded allocation arithmetic without assuming unused bytes are zero.

- [x] Impossible allocation metadata blocks semantic exposure of memo payloads.

- [x] Task 2.2.1 is complete for block sizes 1, 64, 512, and malformed variants.

### Task 2.2.2 — Resolve DBF Memo Pointers

**Description:** Interpret each four-byte DBF memo field as a little-endian block
number with zero representing an empty memo.

#### Subtask 2.2.2.1 — Compute Memo Offsets Safely

**Description:** Multiply block number by effective block size using checked
arithmetic and validate the memo-header range before reading it.

- [x] Overflow, before-header, and beyond-file pointers produce stable findings.

#### Subtask 2.2.2.2 — Preserve Pointer Provenance

**Description:** Retain the DBF record, field, raw pointer bytes, block number,
calculated offset, and resolution result.

- [x] Multiple references to one block remain distinguishable by source field while sharing resolved block identity.

- [x] Task 2.2.2 is complete for empty, valid, shared, and invalid pointers.

### Task 2.2.3 — Decode Memo Blocks

**Description:** Parse the big-endian type and payload length followed by a
bounds-checked payload while preserving source block type and allocation bytes.

#### Subtask 2.2.3.1 — Validate Payload Bounds

**Description:** Check header availability, declared payload end, file end, and
configured memo-size limit before slicing.

- [x] Truncated and excessive lengths never yield a guessed or partial valid payload.

#### Subtask 2.2.3.2 — Preserve Opaque and Padding Bytes

**Description:** Store raw block-header bytes, payload bytes, allocation extent,
and padding needed to compare untouched storage exactly.

- [x] Unknown block types are retained with a warning and are never decoded as text automatically.

- [x] Task 2.2.3 is complete with bounded blocks, shared blocks, unknown types, and overlaps covered.

## Section 2.3 — Encoding, Fidelity, and Physical Findings

**Description:** Layer explicit text decoding over raw physical values without
allowing Unicode conversion to erase or normalize source bytes.

### Task 2.3.1 — Implement Code-Page Resolution

**Description:** Map supported DBF code-page metadata to explicit decoders and
represent unknown or conflicting metadata as findings.

#### Subtask 2.3.1.1 — Implement Strict Windows-1252 Support

**Description:** Decode supported text to UTF-8 while retaining original bytes
and implement strict round-trip encoding for the initial write-compatible page.

- [ ] Unrepresentable text is rejected without producing replacement bytes.

#### Subtask 2.3.1.2 — Preserve Unsupported Encodings

**Description:** Keep all raw content inspectable when text decoding is unknown
or invalid, and prevent later planners from claiming safe writes.

- [ ] Decode findings distinguish unsupported metadata from invalid byte sequences.

- [ ] Task 2.3.1 is complete with ASCII, extended Windows-1252, unknown-page, and invalid-text cases.

### Task 2.3.2 — Define Physical Fidelity Views

**Description:** Make unchanged physical structures comparable without requiring
a rewrite of the source container.

#### Subtask 2.3.2.1 — Retain Raw Container Regions

**Description:** Retain DBF header, descriptors, records, EOF/trailing bytes and
FPT header, blocks, opaque content, padding, and unused ranges.

- [ ] Every decoded value has enough provenance to explain its bytes without normalizing unrelated regions.

#### Subtask 2.3.2.2 — Produce Deterministic Physical Summaries

**Description:** Provide bounded summaries of offsets, lengths, hashes, and
findings for golden tests without embedding full proprietary content.

- [ ] Equal byte snapshots produce equal summaries and finding order.

- [ ] Task 2.3.2 is complete with stable serialized summaries for all golden vectors.

## Section 2.4 — Phase 2 Integration Tests

**Description:** Prove DBF and FPT decoding together across valid, unusual, and
malformed generated pairs while preserving opaque bytes and deterministic results.

### Task 2.4.1 — Exercise Valid Physical Variants

**Description:** Parse generated pair matrices varying schema, record state,
memo pointer, block size, payload type, padding, and code page.

#### Subtask 2.4.1.1 — Run Golden Mixed-Endian Vectors

**Description:** Assert exact values and offsets for little-endian DBF integers,
little-endian memo pointers, and big-endian FPT metadata.

- [ ] Each vector asserts both semantic physical values and their raw source spans.

#### Subtask 2.4.1.2 — Run Property-Based Valid-Pair Checks

**Description:** Generate bounded valid containers and verify deterministic parse,
pointer resolution, non-overlapping spans, and raw-byte retention.

- [ ] Failures report a replayable seed and minimized input.

- [ ] Task 2.4.1 is complete for effective block sizes 1, 64, and 512.

### Task 2.4.2 — Exercise Malformed and Adversarial Inputs

**Description:** Seed truncation and corrupted arithmetic at every physical
boundary and assert bounded structured failure.

#### Subtask 2.4.2.1 — Test DBF Failures

**Description:** Cover short headers, unterminated descriptors, width mismatch,
invalid markers, excessive counts, record truncation, and arithmetic overflow.

- [ ] No malformed DBF case raises, loops indefinitely, or allocates beyond configured limits.

#### Subtask 2.4.2.2 — Test FPT Failures

**Description:** Cover short headers, invalid block sizes, out-of-range pointers,
short block headers, excessive payloads, overlap, and allocation overflow.

- [ ] No invalid memo is exposed as a valid payload and all failures have stable codes.

- [ ] Task 2.4.2 is complete with deterministic finding order across repeated runs.

### Task 2.4.3 — Prove Raw Fidelity

**Description:** Compare every input region to its retained representation and
show that the physical parser does not modify or normalize source bytes.

#### Subtask 2.4.3.1 — Verify Opaque Content Preservation

**Description:** Seed unknown descriptor bytes, deleted records, binary memos,
OLE-like payloads, padding, and trailing data.

- [ ] All seeded opaque regions can be recovered byte-for-byte with original offsets.

#### Subtask 2.4.3.2 — Verify Parse Determinism

**Description:** Parse identical snapshots repeatedly and compare values,
findings, ordering, spans, and physical summaries.

- [ ] No result depends on process order, wall-clock time, locale, or filesystem state.

- [ ] Task 2.4.3 is complete with deterministic results under the full Phase 2 suite.

## Phase 2 Completion Evidence

**Description:** Record proof only after every Phase 2 task and integration test
is complete.

- [ ] DBF and FPT unit-test commands and golden-vector locations are linked.
- [ ] Property-based results include reproducible seed handling.
- [ ] Malformed-input tests prove bounded, non-raising behavior.
- [ ] Raw and opaque byte-fidelity assertions pass.
- [ ] No codec function performs filesystem or MCP side effects.
- [ ] Phase status and the stream index are updated only after all evidence is linked.

## Connections

**Description:** Map this phase to governing current-truth requirements and
adjacent planning documents. These links provide traceability, not verification.

- Requirements: `vfp_mcp.codec.dbf_structure`,
  `vfp_mcp.codec.memo_pointer`, `vfp_mcp.codec.fpt_structure`,
  `vfp_mcp.codec.memo_block`, `vfp_mcp.codec.lossless_encoding`,
  `vfp_mcp.codec.raw_fidelity`, `vfp_mcp.codec.pure_planning`,
  `vfp_mcp.acceptance.codec_evidence`
- Decision: `vfp_mcp.custom_vfp_codec`
- Previous phase: [Phase 1](phase-01-contract-safety-and-test-foundations.md)
- Next phase: [Phase 3](phase-03-semantic-source-model-and-validation.md)
- Stream: [Milestone 0](README.md)
