---
title: "Phase 6: Native Acceptance and Milestone Decision"
kind: note
created: 2026-09-10
maturity: developing
tags:
  - planning
  - milestone-0
  - native-acceptance
  - decision-gate
aliases: []
---

# Phase 6: Native Acceptance and Milestone Decision

**Description:** Execute the native VFP6 and VFP9 acceptance matrix, validate its
hash-bound evidence, resolve codec risks, and record an explicit `accept`,
`revise`, or `stop` decision for transition to Milestone 1.

**Status:** Planned

**Dependencies:** All Phase 1 through Phase 5 deliverables. VFP6 acceptance
requires the external VFP6 machine and human operator established in Phase 4.

## Section 6.1 — Acceptance Bundle and Reproducibility

**Description:** Finalize the schemas, commands, evidence index, and validation
rules used to admit both automated and human native results.

### Task 6.1.1 — Finalize the Evidence Schema

**Description:** Version the JSON and Markdown formats against the actual edit
matrix while preserving the Phase 1 hash-binding and review requirements.

#### Subtask 6.1.1.1 — Define Scenario and Artifact Records

**Description:** Represent source and result pair members, hashes, sizes, VFP
version, IDE version, operation, expected change, observed change, and outcome.

- [ ] Each scenario binds all observations to exact source and result bytes.

#### Subtask 6.1.1.2 — Define Human Action and Signoff Records

**Description:** Require the operator to record open, inspect, save, reopen, and
compile steps, visible findings, anomalies, and final reviewer approval.

- [ ] A scenario cannot pass with omitted required action or an unchecked review item.

- [ ] Task 6.1.1 is complete with schema validation examples for every edit class and VFP version.

### Task 6.1.2 — Implement Evidence Validation

**Description:** Validate structure, hashes, cross-file references, required
actions, allowed outcomes, and evidence completeness without trusting filenames.

#### Subtask 6.1.2.1 — Validate Integrity and Relationships

**Description:** Recompute all available hashes, enforce complete pairs, match
source and result identities, and ensure Markdown signoff references the JSON ID.

- [ ] Tampered, swapped, missing, duplicate, or orphaned artifacts fail with stable codes.

#### Subtask 6.1.2.2 — Validate Acceptance Coverage

**Description:** Compare admitted records with the required version/edit/action
matrix and report every missing or non-passing cell explicitly.

- [ ] Self-reparse or an automated-only record cannot satisfy a native matrix cell.

- [ ] Task 6.1.2 is complete with deterministic validation output.

### Task 6.1.3 — Create the Evidence Index and Reproduction Guide

**Description:** Provide one bounded entry point for reviewing automated test
results, native records, unresolved findings, and the milestone decision.

#### Subtask 6.1.3.1 — Define the Evidence Index

**Description:** List each required outcome, its verification command or native
record, exact artifact hashes, review state, and governing requirement IDs.

- [ ] Missing evidence remains visibly incomplete rather than inferred from nearby results.

#### Subtask 6.1.3.2 — Define Reproduction Commands

**Description:** Document commands for automated suites and evidence validation
from a clean checkout, plus separate human steps for VFP9 and VFP6.

- [ ] Automated reproduction needs no original application tree or VFP process.

- [ ] Task 6.1.3 is complete when a reviewer can reproduce every non-native evidence item from the guide.

## Section 6.2 — Version-Native Edit Acceptance

**Description:** Test codec-produced disposable pairs in their originating VFP
versions through human-operated IDE workflows and record observed behavior.

### Task 6.2.1 — Execute the VFP9 Matrix Locally

**Description:** Use the local VFP9 IDE only with dependency-free synthetic
fixtures and disposable edited copies produced by the accepted Phase 5 planner.

#### Subtask 6.2.1.1 — Accept a Property Edit

**Description:** Open, inspect, save, close, reopen, and compile the edited form;
confirm the property value, designer usability, and absence of unrelated changes.

- [ ] JSON evidence, result hashes, observations, and Markdown signoff are complete.

#### Subtask 6.2.1.2 — Accept a Named Method Edit

**Description:** Open, inspect, save, close, reopen, and compile the method-edited
form; confirm sibling source and observe `OBJCODE` regeneration behavior.

- [ ] JSON evidence, result hashes, observations, and Markdown signoff are complete.

#### Subtask 6.2.1.3 — Record Native Storage Effects

**Description:** Compare before-edit, codec-result, and IDE-saved pairs to record
timestamp, `OBJCODE`, record-order, memo-allocation, and other native rewrites.

- [ ] Every observed difference is classified as understood, constrained, or blocking.

- [ ] Task 6.2.1 is complete with all VFP9 matrix cells reviewed and hash-bound.

### Task 6.2.2 — Execute the VFP6 Matrix Externally

**Description:** Send only the approved synthetic fixtures, disposable edits,
instructions, and evidence templates to the external VFP6 operator.

#### Subtask 6.2.2.1 — Accept a Property Edit

**Description:** Have VFP6 open, inspect, save, close, reopen, and compile the
edited native VFP6 form and record the same property and fidelity observations.

- [ ] Returned JSON evidence, result hashes, observations, and Markdown signoff validate locally.

#### Subtask 6.2.2.2 — Accept a Named Method Edit

**Description:** Have VFP6 open, inspect, save, close, reopen, and compile the
method-edited form and record sibling preservation and `OBJCODE` behavior.

- [ ] Returned JSON evidence, result hashes, observations, and Markdown signoff validate locally.

#### Subtask 6.2.2.3 — Record Native Storage Effects

**Description:** Compare source, codec result, and VFP6-saved artifacts for
timestamp, `OBJCODE`, record order, allocation, and version-specific rewrites.

- [ ] Every observed difference is classified as understood, constrained, or blocking.

- [ ] Task 6.2.2 is complete with all VFP6 matrix cells reviewed and hash-bound.

### Task 6.2.3 — Compare Version Behavior

**Description:** Consolidate VFP6 and VFP9 results without requiring unsupported
cross-version behavior.

#### Subtask 6.2.3.1 — Compare Accepted Invariants

**Description:** Identify shared requirements for pair validity, property and
method visibility, compilation, sibling preservation, and designer round trips.

- [ ] Common invariants are supported by independent native records for both versions.

#### Subtask 6.2.3.2 — Record Permitted Differences

**Description:** Document version-specific timestamp, memo, metadata, and IDE-save
behavior and translate each difference into an implementation constraint or risk.

- [ ] Cross-opening VFP6 artifacts in VFP9 is labeled supplemental and VFP6 acceptance of VFP9-only features is not required.

- [ ] Task 6.2.3 is complete with a reviewed cross-version findings table.

## Section 6.3 — Findings, Risk Disposition, and Milestone Decision

**Description:** Convert automated and native evidence into explicit support
constraints and decide whether work may transition to the read-only MCP milestone.

### Task 6.3.1 — Consolidate the Risk Ledger

**Description:** Record each unresolved physical, semantic, encoding, fidelity,
fixture, and native-compatibility finding with impact and evidence.

#### Subtask 6.3.1.1 — Classify Findings

**Description:** Mark findings as resolved, supported constraint, deferred with
no Milestone 1 impact, requires revision, or blocking.

- [ ] Every classification names its evidence and the affected requirement or future milestone.

#### Subtask 6.3.1.2 — Resolve Milestone 0 Open Questions

**Description:** Conclude the spike's timestamp, `OBJCODE`, record-order, encoding,
opaque-content, and memo-allocation investigations at the level required for reads.

- [ ] No Milestone 0 completion claim depends on an unexplained critical finding.

- [ ] Task 6.3.1 is complete with a reviewed and fully linked risk ledger.

### Task 6.3.2 — Record the Transition Decision

**Description:** Choose exactly one evidence-backed outcome: `accept`, `revise`,
or `stop`.

#### Subtask 6.3.2.1 — Apply Decision Criteria

**Description:** Compare the evidence index with every roadmap completion gate
and list each satisfied, constrained, or failed criterion.

- [ ] The decision is mechanically consistent with the evidence validator's coverage result.

#### Subtask 6.3.2.2 — Define Outcome Consequences

**Description:** For `accept`, state constraints inherited by Milestone 1; for
`revise`, name the exact phase tasks to reopen; for `stop`, record the blocking
technical reason and unsupported capability.

- [ ] Only `accept` authorizes planning or implementation to advance under the Milestone 1 contract.

- [ ] Task 6.3.2 is complete with dated reviewer approval and immutable evidence references.

### Task 6.3.3 — Synchronize Current Truth

**Description:** Update specifications and supporting documentation only to
reflect behavior and constraints proven by the completed evidence.

#### Subtask 6.3.3.1 — Update Subject Status and Verification

**Description:** Change planned/evolving statements and add verification targets
only when the implementation, automated tests, or admitted native records exist.

- [ ] No planning file is registered as behavioral proof and every new verification target is reproducible.

#### Subtask 6.3.3.2 — Update Architecture Findings

**Description:** Replace Milestone 0 open questions with accepted constraints or
blocking results while preserving later milestone boundaries.

- [ ] The architecture, component design, subject specs, stream index, and decision record agree.

- [ ] Task 6.3.3 is complete with strict SpecLed validation passing.

## Section 6.4 — Phase 6 Integration Tests

**Description:** Run the complete clean-checkout and tamper-resistance gate that
supports the final Milestone 0 decision.

### Task 6.4.1 — Validate the Complete Evidence Bundle

**Description:** Recompute fixture and result hashes, validate JSON schemas and
Markdown signoffs, and compare coverage with the required matrix.

#### Subtask 6.4.1.1 — Validate Passing Evidence

**Description:** Load every admitted automated and native record through the
evidence validator and build the deterministic evidence index.

- [ ] All required VFP6 and VFP9 property/method cells are present and reviewed.

#### Subtask 6.4.1.2 — Run Tamper and Omission Tests

**Description:** Seed changed binaries, wrong hashes, swapped versions, missing
actions, incomplete signoff, duplicate IDs, and automated-only native claims.

- [ ] Every seeded defect prevents a passing milestone coverage result.

- [ ] Task 6.4.1 is complete with all integrity and coverage tests passing.

### Task 6.4.2 — Run the Clean-Checkout Quality Gate

**Description:** Reproduce all non-native results using only repository-owned
dependencies, generated vectors, committed fixtures, and admitted evidence.

#### Subtask 6.4.2.1 — Run Automated Project Checks

**Description:** Run dependency retrieval, formatting check, compilation with
warnings as errors, unit/property/integration/malformed/safety tests, and strict
SpecLed validation.

- [ ] Every command and toolchain version is recorded in the evidence index.

#### Subtask 6.4.2.2 — Verify Isolation and Repository Cleanliness

**Description:** Confirm tests do not access original source roots, mutate
committed fixtures, require a VFP process, or leave unexplained tracked changes.

- [ ] The full automated gate passes from an isolated clean checkout.

- [ ] Task 6.4.2 is complete with reproducible logs or structured summaries linked.

### Task 6.4.3 — Validate the Milestone Decision

**Description:** Ensure the recorded outcome follows mechanically from completion
gates, test results, native coverage, and risk disposition.

#### Subtask 6.4.3.1 — Reject Premature Acceptance

**Description:** Temporarily remove one required native record or introduce one
blocking risk and confirm that `accept` becomes invalid.

- [ ] The validator cannot pass on self-reparse, compilation alone, or waived evidence.

#### Subtask 6.4.3.2 — Reproduce the Final Index

**Description:** Regenerate the final evidence index and compare its coverage,
hashes, constraints, and outcome with the reviewed committed record.

- [ ] The regenerated index is deterministic and supports the exact recorded decision.

- [ ] Task 6.4.3 is complete with the final milestone gate passing for the selected outcome.

## Phase 6 Completion Evidence

**Description:** Record the final Milestone 0 proof only after every Phase 6 task
and integration test is complete.

- [ ] Validated VFP9 property and named-method native evidence is linked.
- [ ] Validated VFP6 property and named-method native evidence is linked.
- [ ] Timestamp, `OBJCODE`, record-order, encoding, and opaque-content findings are dispositioned.
- [ ] The complete automated quality gate passes from a clean checkout.
- [ ] The tamper and premature-acceptance tests pass.
- [ ] The evidence index and reviewed `accept`, `revise`, or `stop` decision are linked.
- [ ] Subject specs, architecture, phase status, and stream status reflect only proven results.

## Connections

**Description:** Map this phase to governing current-truth requirements and the
completed planning stream. These links provide traceability, not verification.

- Requirements: `vfp_mcp.acceptance.codec_evidence`,
  `vfp_mcp.acceptance.mutation_footprint`,
  `vfp_mcp.acceptance.native_edit_matrix`,
  `vfp_mcp.acceptance.version_compatibility`,
  `vfp_mcp.acceptance.write_release_gates`,
  `vfp_mcp.acceptance.structural_release_gates`,
  `vfp_mcp.acceptance.quality_gate`,
  `vfp_mcp.mutation.timestamp_gate`, `vfp_mcp.mutation.method_objcode`
- Decisions: `vfp_mcp.versioned_capability_rollout`,
  `vfp_mcp.source_access_boundary`, `vfp_mcp.guarded_pair_transactions`
- Previous phase: [Phase 5](phase-05-targeted-memo-edit-spike.md)
- Next phase: Milestone 1 planning, only after an `accept` decision
- Stream: [Milestone 0](README.md)
