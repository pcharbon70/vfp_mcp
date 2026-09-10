---
title: "Phase 4: Native Fixture Corpus"
kind: note
created: 2026-09-10
maturity: developing
tags:
  - planning
  - milestone-0
  - fixtures
  - native-vfp
aliases: []
---

# Phase 4: Native Fixture Corpus

**Description:** Establish independently authored, sanitized, dependency-free
VFP9 and VFP6 fixture corpora with reproducible provenance, human approval, and
golden semantic manifests.

**Status:** Planned

**Dependencies:** Phase 1 intake/evidence protocol and Phase 3 semantic model.
VFP9 work uses the local human-operated IDE; VFP6 work requires an external VFP6
machine and documented handoff.

## Section 4.1 — VFP9 Synthetic Fixture Authoring

**Description:** Create the minimum native VFP9 forms and class libraries needed
to exercise semantic and physical behavior without using application-derived code.

### Task 4.1.1 — Author the VFP9 Form Set

**Description:** Use the local VFP9 IDE to create closed, synthetic SCX/SCT pairs
covering representative form structures.

#### Subtask 4.1.1.1 — Create Basic and Nested Forms

**Description:** Author one minimal property/method form and one nested-container
form with synthetic names, values, layout, and event bodies.

- [ ] Each form opens without a DBC, table, connection, external class, application path, or startup code.

#### Subtask 4.1.1.2 — Create Grid and Column Form

**Description:** Author a form containing a grid, columns, nested controls, and
repeated local names in distinct containers to exercise path identity.

- [ ] The fixture records intended hierarchy and geometry in its expected manifest.

- [ ] Task 4.1.1 is complete with closed pairs, hashes, and native authoring evidence.

### Task 4.1.2 — Author the VFP9 Class-Library Set

**Description:** Create a closed, synthetic VCX/VCT library containing base and
derived classes with properties and multiple methods.

#### Subtask 4.1.2.1 — Create Base and Derived Classes

**Description:** Exercise class identity, inheritance metadata, nested members,
property overrides, and named method source without external `CLASSLOC` values.

- [ ] All required classes reside in the admitted pair and have synthetic content.

#### Subtask 4.1.2.2 — Add Safe Opaque Content if Available

**Description:** Add a native-created opaque or binary memo only when it can be
created without external files or live dependencies; otherwise record the gap.

- [ ] Opaque coverage is either admitted with review or explicitly deferred with a reason and synthetic generated-vector coverage.

- [ ] Task 4.1.2 is complete with a closed pair and expected class manifest.

### Task 4.1.3 — Review and Quarantine VFP9 Outputs

**Description:** Close the IDE, copy only the minimum pairs into the ignored drop,
and run automated inventory before human review and promotion.

#### Subtask 4.1.3.1 — Run Automated Intake

**Description:** Inventory records, memo fields, bindings, code strings,
`CLASSLOC`, environment paths, and companion hashes without executing the form.

- [ ] Unsafe or unexplained content prevents promotion and remains quarantined.

#### Subtask 4.1.3.2 — Complete Human Review

**Description:** Confirm synthetic content, complete pairing, closed dependencies,
intended structures, and absence of proprietary or identifying material.

- [ ] The reviewer signs the Markdown checklist bound to the inventory JSON and pair hashes.

- [ ] Task 4.1.3 is complete only after approved VFP9 pairs are promoted to `test/fixtures/vfp9`.

## Section 4.2 — External VFP6 Fixture Handoff

**Description:** Obtain genuinely VFP6-authored fixtures and evidence without
claiming that local VFP9 or synthetic bytes substitute for VFP6 authority.

### Task 4.2.1 — Prepare the VFP6 Handoff Package

**Description:** Create a self-contained instruction and evidence package for a
human operator on an external VFP6 machine.

#### Subtask 4.2.1.1 — Specify the Fixture Matrix

**Description:** Request VFP6-native equivalents of the basic, nested, grid, and
class-library fixtures while avoiding VFP9-only features.

- [ ] Each requested artifact has exact synthetic names, intended content, and expected pair members.

#### Subtask 4.2.1.2 — Specify Safe Authoring and Return Steps

**Description:** Require an isolated empty workspace, no application projects or
data, IDE closure before hashing, and return of only pairs plus evidence files.

- [ ] The operator can complete the handoff without accessing LecoWin2, SBT, or production data.

- [ ] Task 4.2.1 is complete with a dry review of the package by someone other than its author.

### Task 4.2.2 — Receive and Verify the VFP6 Package

**Description:** Admit the returned package first to quarantine, validate hashes
and evidence, and independently scan content before promotion.

#### Subtask 4.2.2.1 — Validate Returned Evidence

**Description:** Verify VFP6 IDE identity, scenario completion, exact pair hashes,
operator signoff, and absence of undeclared files.

- [ ] Hash or metadata mismatch rejects the package without altering returned artifacts.

#### Subtask 4.2.2.2 — Run Automated and Human Intake Review

**Description:** Apply the same dependency, content, pairing, and sanitization
checks used for VFP9, treating all returned binaries as untrusted input.

- [ ] The package remains unexecuted and quarantined until both reviews pass.

- [ ] Task 4.2.2 is complete only after approved pairs are promoted to `test/fixtures/vfp6`.

## Section 4.3 — Promotion and Golden Manifests

**Description:** Make admitted fixtures reproducible test inputs with provenance
separate from expected semantic results.

### Task 4.3.1 — Harden Fixture Intake and Promotion

**Description:** Ensure `scripts/intake-fixtures.ps1` validates only the ignored
fixture-drop directories and promotes complete, reviewed pairs deterministically.

#### Subtask 4.3.1.1 — Enforce Version and Pair Rules

**Description:** Accept only approved SCX/SCT or VCX/VCT pairs in the declared
VFP6 or VFP9 drop and reject incomplete, duplicate, or unexpected file sets.

- [ ] Intake never scans a broader external tree or follows source references.

#### Subtask 4.3.1.2 — Make Promotion Reproducible

**Description:** Verify source hashes immediately before copying, produce an
admission manifest, and refuse overwrite when committed content differs.

- [ ] Promoted pair bytes exactly match their reviewed source hashes.

- [ ] Task 4.3.1 is complete with positive, rejection, and idempotency tests.

### Task 4.3.2 — Create Golden Semantic Manifests

**Description:** Store expected semantic content as reviewable text separate from
the native binary pair and generate actual results only through the codec.

#### Subtask 4.3.2.1 — Define Manifest Content

**Description:** Record pair kind/version, object identities, paths, containment,
selected properties, method names and hashes, record order, and expected findings.

- [ ] Manifests avoid unnecessary source bodies and contain no proprietary or personal data.

#### Subtask 4.3.2.2 — Review Cross-Version Expectations

**Description:** Mark which VFP6 and VFP9 results must be semantically equivalent
and which physical or version-specific differences are intentional.

- [ ] Cross-version comparison never requires VFP6 to accept VFP9-only features.

- [ ] Task 4.3.2 is complete when every admitted pair has a reviewed expected manifest.

### Task 4.3.3 — Record Fixture Provenance

**Description:** Link committed artifacts to their authoring evidence without
placing operator-sensitive or workstation-specific details in runtime tests.

#### Subtask 4.3.3.1 — Record Immutable Identity

**Description:** Store member hashes, sizes, pair kind, VFP version, evidence ID,
and admission date in a deterministic fixture index.

- [ ] A test detects any binary fixture change not accompanied by a reviewed provenance update.

#### Subtask 4.3.3.2 — Separate Native Evidence from Fixtures

**Description:** Keep checklists and JSON evidence in the approved evidence area
while fixture tests consume only committed pairs, manifests, and safe identifiers.

- [ ] The separation supports audit without making test behavior depend on a human workstation path.

- [ ] Task 4.3.3 is complete with all links and hashes validated.

## Section 4.4 — Phase 4 Integration Tests

**Description:** Parse, compare, and challenge every admitted native pair and the
intake workflow without opening a VFP IDE or accessing external application trees.

### Task 4.4.1 — Parse the Complete Admitted Corpus

**Description:** Run the physical and semantic codec against every promoted VFP6
and VFP9 form and class-library pair.

#### Subtask 4.4.1.1 — Compare Golden Manifests

**Description:** Assert pair identity, objects, paths, containment, properties,
methods, record order, physical metadata, and expected findings.

- [ ] Every admitted pair matches its reviewed manifest with no unexplained critical finding.

#### Subtask 4.4.1.2 — Compare Cross-Version Semantics

**Description:** Compare the explicitly equivalent VFP6 and VFP9 fixture cases
while retaining and reporting permitted physical differences.

- [ ] Cross-version comparisons are deterministic and version policy is explicit.

- [ ] Task 4.4.1 is complete for the entire committed corpus.

### Task 4.4.2 — Exercise Intake and Provenance Defenses

**Description:** Mutate isolated copies of fixture packages and confirm that
unsafe, incomplete, stale, or undeclared content cannot be admitted.

#### Subtask 4.4.2.1 — Seed Intake Rejections

**Description:** Test missing companions, mismatched case, extra files, binding
strings, external paths, data commands, class locations, code, and hash changes.

- [ ] Every seeded hazard fails before promotion and leaves committed fixtures unchanged.

#### Subtask 4.4.2.2 — Verify Idempotent Admission

**Description:** Re-run intake for an unchanged approved package and compare
manifests, hashes, outputs, and repository status.

- [ ] Repeated validation is deterministic and introduces no binary change.

- [ ] Task 4.4.2 is complete with all original application paths absent from test inputs and outputs.

### Task 4.4.3 — Prove Fixture Independence

**Description:** Demonstrate that committed fixtures are closed synthetic assets
and that tests neither need nor follow live environment references.

#### Subtask 4.4.3.1 — Run Dependency Scans

**Description:** Scan record fields and textual memos for DBC, DBF, connection,
executable, application-root, external class, credential, and identifying content.

- [ ] No admitted fixture contains an unresolved live dependency or prohibited content.

#### Subtask 4.4.3.2 — Run the Corpus Offline

**Description:** Execute the fixture tests with external source-root variables
unset and no VFP process required.

- [ ] All automated corpus tests pass using repository-owned assets only.

- [ ] Task 4.4.3 is complete with the offline command and results recorded.

## Phase 4 Completion Evidence

**Description:** Record proof only after every Phase 4 task and integration test
is complete.

- [ ] VFP9 authoring JSON, hashes, and Markdown signoff are admitted.
- [ ] VFP6 external authoring JSON, hashes, and Markdown signoff are admitted.
- [ ] Every committed pair has provenance and a reviewed semantic manifest.
- [ ] Intake rejection, idempotency, corpus parsing, and dependency tests pass.
- [ ] No original application artifact is committed or executed.
- [ ] Phase status and the stream index are updated only after all evidence is linked.

## Connections

**Description:** Map this phase to governing current-truth requirements and
adjacent planning documents. These links provide traceability, not verification.

- Requirements: `vfp_mcp.acceptance.synthetic_native_fixtures`,
  `vfp_mcp.acceptance.no_live_dependencies`,
  `vfp_mcp.acceptance.raw_intake_quarantine`,
  `vfp_mcp.acceptance.fixture_review`,
  `vfp_mcp.acceptance.codec_evidence`,
  `vfp_mcp.acceptance.version_compatibility`
- Decision: `vfp_mcp.source_access_boundary`
- Previous phase: [Phase 3](phase-03-semantic-source-model-and-validation.md)
- Next phase: [Phase 5](phase-05-targeted-memo-edit-spike.md)
- Stream: [Milestone 0](README.md)
