---
title: "Phase 1: Contract, Safety, and Test Foundations"
kind: note
created: 2026-09-10
maturity: developing
tags:
  - planning
  - milestone-0
  - safety
  - testing
aliases: []
---

# Phase 1: Contract, Safety, and Test Foundations

**Description:** Establish the executable boundaries, domain contracts, test
infrastructure, and safe fixture/evidence workflow required before parsing or
editing Visual FoxPro source pairs.

**Status:** Complete

**Dependencies:** None. This phase is the prerequisite for every later phase.

## Section 1.1 — Milestone Contract and Safety Boundary

**Description:** Convert the architectural Milestone 0 boundary and repository
isolation policy into explicit implementation and test constraints.

### Task 1.1.1 — Define Milestone 0 Deliverables and Exclusions

**Description:** Record exactly what Milestone 0 must prove and which runtime or
write capabilities must remain absent.

#### Subtask 1.1.1.1 — Define Required Outcomes

**Description:** Express the physical codec, semantic model, native fixtures,
targeted edit spike, and native acceptance bundle as separately testable
deliverables.

- [x] The contract names an observable result and evidence type for every required outcome.

#### Subtask 1.1.1.2 — Define Excluded Capabilities

**Description:** State that MCP tools, production file transactions, structural
editing, IDE automation, and application-data access are outside this milestone.

- [x] Tests can assert that excluded runtime modules and tool registrations are not introduced by Milestone 0.

- [x] Task 1.1.1 is complete with its contract reviewed against the architecture milestone.

### Task 1.1.2 — Encode the Development Isolation Rules

**Description:** Make repository isolation enforceable in default development
and test workflows rather than relying only on operator memory.

#### Subtask 1.1.2.1 — Define Permitted Test Inputs

**Description:** Permit generated binary vectors, committed synthetic fixtures,
and explicitly created disposable copies while denying implicit external roots.

- [x] The default test configuration resolves all inputs within the repository or its isolated temporary directory.

#### Subtask 1.1.2.2 — Define Forbidden Operations

**Description:** Prevent tests from opening, modifying, compiling, executing, or
running tools against original LecoWin2 or SBT sources and all associated data.

- [x] A guard produces a clear failure before a prohibited root or live dependency can be used.

- [x] Task 1.1.2 is complete with positive and negative boundary examples documented.

## Section 1.2 — Codec and Domain Contracts

**Description:** Fix the pure interfaces, domain values, structured failures,
and resource limits that later phases will implement.

### Task 1.2.1 — Define Immutable Inputs and Parse Results

**Description:** Center parsing on caller-supplied immutable bytes so the codec
cannot perform hidden file access.

#### Subtask 1.2.1.1 — Specify `PairSnapshot`

**Description:** Define a snapshot containing pair kind, logical identity,
individual member identities and hashes, and DBF/FPT byte strings.

- [x] The type contract distinguishes SCX/SCT from VCX/VCT and requires both companion members.

#### Subtask 1.2.1.2 — Specify the Public Parse Boundary

**Description:** Define `VfpMcp.Codec.parse_pair/2` to return either a complete
semantic document or structured fatal findings, without filesystem side effects.

- [x] Parse return types, warning ownership, and fatal-error behavior are documented and tested at the boundary.

- [x] Task 1.2.1 is complete with typespec-oriented examples for success and failure.

### Task 1.2.2 — Define Domain Values and Pure Edit Plans

**Description:** Specify the minimum provenance-bearing domain model needed for
semantic parsing and the later edit spike.

#### Subtask 1.2.2.1 — Specify Core Domain Structures

**Description:** Define `Document`, `Object`, `Finding`, physical spans, memo
references, and pair identity without adding MCP presentation concerns.

- [x] Each semantic value can be traced to its source record, field, memo block, and byte span where applicable.

#### Subtask 1.2.2.2 — Specify Planner Results

**Description:** Define `EditPlan` as source-hash-bound DBF patches, FPT appends,
expected footprint, and semantic postcondition that can be materialized purely.

- [x] The contract cannot write a file, omit the source identity, or authorize a production transaction.

- [x] Task 1.2.2 is complete with property and method plan examples.

### Task 1.2.3 — Define Findings and Resource Limits

**Description:** Establish stable diagnostics and hard bounds before processing
malformed or adversarial binary input.

#### Subtask 1.2.3.1 — Define Finding Taxonomy

**Description:** Give each finding a stable code, severity, physical or semantic
location, safe message, and bounded evidence map.

- [x] Fatal parsing errors, mutation-blocking errors, preserved-content warnings, and compatibility notes are distinguishable.

#### Subtask 1.2.3.2 — Define Safety Limits

**Description:** Set configurable defaults for member byte size, records,
fields, memo payload, memo blocks, findings, hierarchy depth, and parsed text.

- [x] Every limit has a stable exceeded-limit finding and is enforced before unbounded allocation or traversal.

- [x] Task 1.2.3 is complete with documented defaults and override rules for tests.

## Section 1.3 — Fixture and Native-Evidence Protocol

**Description:** Define how native artifacts enter the repository and how VFP6
and VFP9 observations become reproducible, hash-bound evidence.

### Task 1.3.1 — Define Fixture Lifecycle and Quarantine

**Description:** Separate raw intake, review, promotion, committed fixtures, and
disposable mutation outputs with explicit transitions.

#### Subtask 1.3.1.1 — Define Intake States

**Description:** Document drop, inventory, automated rejection, human review,
promotion, and admitted states without ever executing raw intake.

- [x] Each transition identifies its permitted input directory, output directory, and required evidence.

#### Subtask 1.3.1.2 — Define Sanitization and Dependency Rules

**Description:** Require synthetic names and logic and prohibit credentials,
identifying content, application paths, tables, databases, connections, and
external class dependencies.

- [x] Promotion fails when either automated inventory or human review cannot establish safe isolation.

- [x] Task 1.3.1 is complete with an auditable promotion checklist.

### Task 1.3.2 — Define the Native Evidence Bundle

**Description:** Pair machine-readable results with human signoff for every
version-native authoring or edit-acceptance run.

#### Subtask 1.3.2.1 — Define JSON Evidence

**Description:** Specify a versioned JSON record containing scenario ID, VFP
version, IDE version, fixture and result hashes, exact actions, observations,
timestamps, operator, and outcome.

- [x] A schema rejects missing pair members, invalid hashes, unknown outcomes, and result hashes not bound to the declared inputs.

#### Subtask 1.3.2.2 — Define Markdown Review Signoff

**Description:** Provide a human checklist covering synthetic content, closed
pairs, dependency removal, native actions, observations, anomalies, and review.

- [x] The checklist references the JSON record and exact hashes rather than duplicating or weakening machine-readable evidence.

#### Subtask 1.3.2.3 — Define Version-Specific Operation

**Description:** Assign VFP9 authoring and acceptance to the local human-operated
IDE and VFP6 work to a documented external-machine handoff.

- [x] Neither workflow requires automated IDE control or access to an original application tree.

- [x] Task 1.3.2 is complete with sample passing and failing evidence packages.

### Task 1.3.3 — Establish Test Infrastructure

**Description:** Provide deterministic builders and property-based testing tools
for binary inputs and evidence validation.

#### Subtask 1.3.3.1 — Add the Property-Test Dependency

**Description:** Add `{:stream_data, "~> 1.4", only: :test}` without changing the
runtime dependency graph.

- [x] A minimal seeded property test runs under `mix test` and is reproducible when its seed is reported.

#### Subtask 1.3.3.2 — Create Binary Pair Builders

**Description:** Build valid and deliberately malformed DBF/FPT byte strings
from declarative test input without depending on VFP or external files.

- [x] Builders control endianness, offsets, block size, record schema, memo pointers, and raw opaque regions.

- [x] Task 1.3.3 is complete when later codec tests can express cases without hand-editing binary fixtures.

## Section 1.4 — Phase 1 Integration Tests

**Description:** Prove that the contracts, isolation rules, builders, and
evidence protocol work together before physical codec implementation starts.

### Task 1.4.1 — Exercise the Safe Default Workflow

**Description:** Run the repository test workflow with no external VFP roots or
IDE dependencies and verify that only isolated inputs are used.

#### Subtask 1.4.1.1 — Test Root and Dependency Rejection

**Description:** Seed path escapes, original-tree candidates, live bindings,
external `CLASSLOC`, and incomplete companion pairs.

- [x] Every unsafe case is rejected before source execution, compilation, or mutation.

#### Subtask 1.4.1.2 — Test Offline Reproducibility

**Description:** Run builders and contract tests repeatedly with fixed seeds and
compare serialized bytes, findings, and evidence output.

- [x] Repeated runs produce byte-identical outputs and stable finding codes.

- [x] Task 1.4.1 is complete with a single documented command for the safe suite.

### Task 1.4.2 — Exercise Evidence Validation End to End

**Description:** Validate a synthetic evidence package and prove that invalid or
tampered variants are rejected.

#### Subtask 1.4.2.1 — Validate a Complete Package

**Description:** Bind a generated pair, a result pair, a JSON record, and a
Markdown signoff through their hashes.

- [x] The validator accepts the complete package and emits a deterministic summary.

#### Subtask 1.4.2.2 — Reject Incomplete and Tampered Packages

**Description:** Change hashes, remove a companion, omit required actions, and
leave human-review items incomplete.

- [x] Each seeded defect produces a specific validation failure and no admitted state.

- [x] Task 1.4.2 is complete with all negative evidence cases passing.

## Phase 1 Completion Evidence

**Description:** Record proof only after every Phase 1 task and integration test
is complete.

- [x] Contract and type documentation are recorded in
  [the Milestone 0 contract](../../../docs/contracts/milestone-0.md) and
  [the codec domain contract](../../../docs/contracts/codec-domain.md).
- [x] The documented [`mix phase1` safe-suite command](../../../docs/testing/phase-1-safe-suite.md)
  passes with 39 tests and strict SpecLed validation.
- [x] The test-only StreamData dependency and
  [deterministic pair builder](../../../test/support/vfp_pair_builder.ex) are present.
- [x] [The Phase 1 integration test](../../../test/integration/phase_1_foundations_test.exs)
  uses in-memory inputs and inert rejection paths; it neither accesses nor requires
  an original LecoWin2 or SBT tree.
- [x] Every Phase 1 item above has linked evidence; the phase status and
  [stream index](README.md) are now `Complete`.

## Connections

**Description:** Map this phase to governing current-truth requirements and
adjacent planning documents. These links provide traceability, not verification.

- Requirements: `vfp_mcp.codec.pure_planning`,
  `vfp_mcp.acceptance.no_live_dependencies`,
  `vfp_mcp.acceptance.raw_intake_quarantine`,
  `vfp_mcp.acceptance.fixture_review`,
  `vfp_mcp.acceptance.evidence_bundle_integrity`,
  `vfp_mcp.acceptance.deterministic_test_vectors`,
  `vfp_mcp.acceptance.phase1_safe_foundation`,
  `vfp_mcp.acceptance.quality_gate`
- Decisions: `vfp_mcp.source_access_boundary`,
  `vfp_mcp.versioned_capability_rollout`
- Previous phase: None
- Next phase: [Phase 2](phase-02-physical-dbf-fpt-codec.md)
- Stream: [Milestone 0](README.md)
