---
title: "Phase 3: Semantic Source Model and Validation"
kind: note
created: 2026-09-10
maturity: developing
tags:
  - planning
  - milestone-0
  - semantic-model
  - validation
aliases: []
---

# Phase 3: Semantic Source Model and Validation

**Description:** Convert physical SCX/SCT and VCX/VCT records into a conservative
semantic document of objects, properties, methods, paths, and containment while
retaining every physical source span and unknown byte.

**Status:** In progress

**Dependencies:** Phase 2 physical codec and Phase 1 domain/finding contracts.

## Section 3.1 — Pair, Document, and Object Model

**Description:** Assemble physical codec results into provenance-bearing domain
values without introducing filesystem, MCP, or mutation side effects.

### Task 3.1.1 — Classify and Parse Source Pairs

**Description:** Validate companion kind and construct one document from a
caller-supplied snapshot and the two physical parse results.

#### Subtask 3.1.1.1 — Enforce Pair Compatibility

**Description:** Require matching SCX/SCT or VCX/VCT identity, retain declared
compatibility target, and report unsupported or contradictory version metadata.

- [x] Mixed or incomplete pair input fails before semantic fields are exposed as valid.

#### Subtask 3.1.1.2 — Propagate Source Identity

**Description:** Carry pair hashes, member hashes, lengths, physical indices,
field spans, memo references, and codec findings into the semantic document.

- [x] Every semantic object and parsed text region can be traced back to exact input bytes.

- [x] Task 3.1.1 is complete for both form and class-library pair kinds.

### Task 3.1.2 — Build Records and Objects

**Description:** Classify relevant source records conservatively while retaining
active, deleted, comment, data-environment, bookend, and unknown records.

#### Subtask 3.1.2.1 — Extract Known Identity Fields

**Description:** Read `CLASS`, `BASECLASS`, `OBJNAME`, `PARENT`, `CLASSLOC`,
reserved metadata, and known memo references only when their physical fields exist.

- [x] Missing, duplicate, malformed, or differently ordered fields become findings rather than positional guesses.

#### Subtask 3.1.2.2 — Preserve Unknown Record Content

**Description:** Keep raw fields, record order, deletion state, unclassified
record types, and opaque memos even when no semantic behavior is attached.

- [x] Semantic construction never drops a physical record or memo reference.

- [x] Task 3.1.2 is complete with stable physical and semantic record indices.

### Task 3.1.3 — Define Document Success and Failure Semantics

**Description:** Distinguish fatal physical failures from recoverable semantic
findings so callers never mistake partial data for a fully valid document.

#### Subtask 3.1.3.1 — Classify Fatal Findings

**Description:** Identify failures that prevent trustworthy pair, record, memo,
or text boundaries and return them through the error result.

- [x] Fatal results do not expose guessed semantic values as valid.

#### Subtask 3.1.3.2 — Retain Recoverable Findings

**Description:** Attach deterministic warnings and mutation-blocking errors to a
document when raw content is bounded and safe to inspect.

- [x] Document validity and mutation eligibility are separate explicit states.

- [x] Task 3.1.3 is complete with boundary tests for fatal, inspectable, and clean documents.

## Section 3.2 — Property and Method Parsing

**Description:** Parse only the VFP text structures needed for precise inspection
and narrow edits while preserving syntax the parser does not understand.

### Task 3.2.1 — Parse Property Memos Conservatively

**Description:** Index property assignments by name and source span without
normalizing original text, ordering, expressions, whitespace, or line endings.

#### Subtask 3.2.1.1 — Recognize Supported Assignments

**Description:** Identify assignment boundaries and decode strings, booleans,
integers, decimals, `.NULL.`, and explicitly tagged dates/datetimes where syntax
is unambiguous.

- [x] Each recognized assignment retains name spelling, raw literal, semantic value, separators, and byte/text spans.

#### Subtask 3.2.1.2 — Preserve Unsupported and Ambiguous Lines

**Description:** Retain comments, blank lines, continuations, expressions,
duplicates, and unknown constructs verbatim and mark unsafe edit targets.

- [x] Parsing an unsupported line never changes neighboring assignment boundaries.

- [x] Task 3.2.1 is complete across CRLF, LF, empty, duplicate, and expression-rich memos.

### Task 3.2.2 — Parse Named Method Blocks Conservatively

**Description:** Index `PROCEDURE` through matching `ENDPROC` blocks while
retaining the full memo and every sibling block verbatim.

#### Subtask 3.2.2.1 — Identify Method Boundaries

**Description:** Recognize case-insensitive procedure markers only at valid line
positions and retain declared names, signature text, body, terminator, and spans.

- [x] Phrases inside strings or comments do not create method boundaries.

#### Subtask 3.2.2.2 — Report Ambiguous Method Structure

**Description:** Detect duplicates, missing terminators, nested or overlapping
boundaries, and unmatched terminators without inventing repair behavior.

- [x] Ambiguous method memos remain inspectable verbatim but are blocked from named-method planning.

- [x] Task 3.2.2 is complete across multiple methods, mixed case, comments, and malformed bookends.

### Task 3.2.3 — Preserve Text and Physical Span Correspondence

**Description:** Keep an exact mapping between decoded text regions and original
memo bytes so later replacement spans are safe and explainable.

#### Subtask 3.2.3.1 — Map Text Spans to Bytes

**Description:** Record byte offsets for parsed property lines and method blocks
using the selected source encoding rather than Unicode character counts.

- [x] Extended Windows-1252 characters before and inside a target produce correct byte spans.

#### Subtask 3.2.3.2 — Retain Verbatim Memo Representations

**Description:** Store original payload bytes, decoded text, line-ending style,
and parse indexes without synthesizing a normalized rendering.

- [x] Re-reading semantic values does not require re-encoding or rewriting the memo.

- [x] Task 3.2.3 is complete with byte-span assertions for all supported text constructs.

## Section 3.3 — Hierarchy, Paths, and Validation

**Description:** Build deterministic containment and canonical full paths from
`OBJNAME` and `PARENT`, explicitly reporting ambiguity and invalid relationships.

### Task 3.3.1 — Resolve Containment

**Description:** Associate each object with its parent using semantic identity
fields rather than physical adjacency or presumed record order.

#### Subtask 3.3.1.1 — Resolve Parent References

**Description:** Build lookup indexes using the documented case policy and
retain unresolved or multiply resolved references as findings.

- [ ] Reordering physical records does not alter an otherwise unambiguous containment graph.

#### Subtask 3.3.1.2 — Detect Invalid Graphs

**Description:** Detect missing parents, self-parenting, cycles, excessive depth,
and incompatible container relationships with bounded traversal.

- [ ] Invalid graphs never loop and each involved physical record remains inspectable.

- [ ] Task 3.3.1 is complete for forms, nested containers, grids, and class-library records.

### Task 3.3.2 — Construct Canonical Object Paths

**Description:** Address controls with deterministic full paths so repeated local
names in distinct containers remain unambiguous.

#### Subtask 3.3.2.1 — Apply Segment Escaping and Case Policy

**Description:** Use slash-separated, percent-escaped path segments with one
shared comparison and canonicalization policy for construction and lookup.

- [ ] Names containing separators, percent characters, spaces, and mixed case round-trip through path parsing.

#### Subtask 3.3.2.2 — Detect Path Ambiguity

**Description:** Report duplicate sibling identities, canonicalization collisions,
and multiple objects resolving to the same full path.

- [ ] Ambiguous paths cannot become mutation targets even when one record appears first.

- [ ] Task 3.3.2 is complete with deterministic path and collision findings.

### Task 3.3.3 — Implement Named Validation Rules

**Description:** Produce deterministic findings for physical-to-semantic,
property, method, hierarchy, and compatibility invariants.

#### Subtask 3.3.3.1 — Implement Stable Rules

**Description:** Give each rule a stable code, documented severity, bounded
evidence, and exact source location where available.

- [ ] Finding output is sorted deterministically by physical location, rule code, and semantic identity.

#### Subtask 3.3.3.2 — Separate Inspectability from Edit Eligibility

**Description:** Define which findings are fatal, which permit read inspection,
and which block the later property or method planner.

- [ ] A document exposes an explicit eligibility result instead of requiring callers to infer it from messages.

- [ ] Task 3.3.3 is complete with a rule matrix and focused tests.

## Section 3.4 — Phase 3 Integration Tests

**Description:** Parse complete generated source pairs into semantic documents
and prove conservative modeling, hierarchy behavior, and raw fidelity end to end.

### Task 3.4.1 — Exercise Representative Semantic Documents

**Description:** Build form and class-library pairs containing properties,
methods, nested containers, grids, columns, data-environment records, and opaque data.

#### Subtask 3.4.1.1 — Assert Semantic Content and Provenance

**Description:** Compare document values, object identity, property and method
spans, hierarchy paths, and findings with explicit expected manifests.

- [ ] Every expected semantic value points to the correct record, field, memo, and byte range.

#### Subtask 3.4.1.2 — Assert Verbatim Preservation

**Description:** Compare all raw records, memo payloads, unsupported lines,
comments, whitespace, line endings, OLE-like content, and record order.

- [ ] Semantic parsing introduces no byte normalization or content loss.

- [ ] Task 3.4.1 is complete for both SCX/SCT and VCX/VCT generated pairs.

### Task 3.4.2 — Exercise Invalid Semantic Structures

**Description:** Seed semantic ambiguity while keeping physical containers valid
and assert stable, bounded validation behavior.

#### Subtask 3.4.2.1 — Test Hierarchy Failures

**Description:** Cover duplicate siblings, missing parents, self-parenting,
cycles, depth limits, escaping collisions, and record-order variation.

- [ ] Each invalid graph produces deterministic findings and no ambiguous path target.

#### Subtask 3.4.2.2 — Test Property and Method Failures

**Description:** Cover duplicate properties, unsupported expressions, malformed
strings, duplicate methods, missing `ENDPROC`, and marker text in comments.

- [ ] Unsafe targets are blocked while original memo bytes remain inspectable.

- [ ] Task 3.4.2 is complete with stable findings across repeated runs.

### Task 3.4.3 — Prove Pure Deterministic Orchestration

**Description:** Parse the same snapshots concurrently and repeatedly without
filesystem, clock, locale, or process-order influence.

#### Subtask 3.4.3.1 — Compare Complete Results

**Description:** Compare object order, path indexes, parsed spans, findings,
physical references, and bounded summaries across runs.

- [ ] Equal snapshots and options always produce structurally equal results.

#### Subtask 3.4.3.2 — Verify No Hidden Effects

**Description:** Assert that parsing starts no processes, reads no paths, emits
no protocol output, and creates no files.

- [ ] The semantic codec remains usable as a pure library in unit tests.

- [ ] Task 3.4.3 is complete with the entire Phase 3 suite passing offline.

## Phase 3 Completion Evidence

**Description:** Record proof only after every Phase 3 task and integration test
is complete.

- [ ] Domain types and parse-boundary documentation are linked.
- [ ] Property, method, hierarchy, and validation tests pass.
- [ ] Generated SCX/SCT and VCX/VCT integration manifests pass.
- [ ] Verbatim content and physical provenance assertions pass.
- [ ] Determinism and no-hidden-effects evidence is recorded.
- [ ] Phase status and the stream index are updated only after all evidence is linked.

## Connections

**Description:** Map this phase to governing current-truth requirements and
adjacent planning documents. These links provide traceability, not verification.

- Requirements: `vfp_mcp.codec.property_edit_scope`,
  `vfp_mcp.codec.method_edit_scope`, `vfp_mcp.codec.semantic_document`,
  `vfp_mcp.codec.hierarchy_integrity`, `vfp_mcp.codec.raw_fidelity`,
  `vfp_mcp.codec.pure_planning`, `vfp_mcp.acceptance.codec_evidence`
- Decisions: `vfp_mcp.custom_vfp_codec`,
  `vfp_mcp.source_access_boundary`
- Previous phase: [Phase 2](phase-02-physical-dbf-fpt-codec.md)
- Next phase: [Phase 4](phase-04-native-fixture-corpus.md)
- Stream: [Milestone 0](README.md)
