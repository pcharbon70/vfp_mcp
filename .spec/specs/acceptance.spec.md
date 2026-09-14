# Fixtures and Acceptance Gates

The evidence policy for format support, safe mutation, native VFP compatibility,
and release sequencing.

## Intent

Require synthetic, version-native fixtures and layered automated plus manual
acceptance before enabling source mutations or higher-risk structural behavior.

```spec-meta
id: vfp_mcp.acceptance
kind: policy
status: active
summary: Isolated fixture admission and native VFP acceptance requirements.
surface:
  - .gitattributes
  - test/fixtures/README.md
  - docs/testing/fixture-authoring-checklist.md
  - docs/research/fixture-intake-investigation.md
  - docs/architecture.md
  - scripts/intake-fixtures.ps1
  - docs/testing/fixture-lifecycle-and-evidence.md
  - docs/testing/native-evidence-signoff-template.md
  - docs/testing/vfp6-handoff.md
  - docs/testing/vfp9-native-workflow.md
  - docs/testing/phase-1-safe-suite.md
  - docs/testing/phase-2-codec-suite.md
  - mix.exs
  - priv/evidence/native-evidence.schema.json
  - lib/vfp_mcp/acceptance/evidence.ex
  - lib/vfp_mcp/acceptance/fixture_admission.ex
  - lib/vfp_mcp/acceptance/fixture_safety.ex
  - test/support/evidence_factory.ex
  - test/support/vfp_pair_builder.ex
  - test/fixtures/evidence/valid/native-evidence.json
  - test/fixtures/evidence/valid/native-evidence-signoff.md
  - test/fixtures/evidence/invalid/native-evidence.json
  - test/fixtures/evidence/invalid/native-evidence-signoff.md
  - test/vfp_mcp/acceptance/evidence_test.exs
  - test/vfp_mcp/acceptance/fixture_admission_test.exs
  - test/vfp_mcp/test_support/pair_builder_test.exs
  - test/integration/phase_1_foundations_test.exs
  - test/integration/phase_2_physical_codec_test.exs
decisions:
  - vfp_mcp.source_access_boundary
  - vfp_mcp.versioned_capability_rollout
  - vfp_mcp.guarded_pair_transactions
```

## Requirements

```spec-requirements
- id: vfp_mcp.acceptance.synthetic_native_fixtures
  statement: Committed acceptance fixtures shall be purpose-built independently in VFP 6 and VFP 9, contain only synthetic content, and include the closed SCX/SCT and VCX/VCT pairs required by the fixture checklist.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.no_live_dependencies
  statement: A runnable fixture shall contain no real DBC, DBF, connection, executable, production path, external application class, or other live application dependency.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.raw_intake_quarantine
  statement: Raw application-derived intake pairs shall remain ignored, local, read-only, uncommitted, and unexecuted and may be used only for isolated parser comparison.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.fixture_review
  statement: Before promotion, automated intake shall inventory records, memo fields, bindings, class locations, code, and strings, and a human shall confirm that only approved synthetic content is present.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.fixture_admission_protocol
  statement: A fixture shall move from version-specific quarantine to admitted status only after passing automated inventory and hash-bound human review, and a rejection shall remain terminal for that artifact.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.evidence_bundle_integrity
  statement: Native evidence shall use a versioned JSON record plus a Markdown signoff bound to the same evidence ID and exact source and result pair hashes, and validation shall reject missing members, malformed hashes, omitted actions, unchecked review items, or mismatched signoff.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.version_native_handoff
  statement: VFP 9 native work shall be performed manually in the local VFP 9 IDE, VFP 6 native work shall use a documented external-machine human handoff, and neither workflow shall automate the IDE or access an original application tree.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.deterministic_test_vectors
  statement: Automated codec tests shall use deterministic in-memory builders that control DBF schema and offsets, DBF and FPT endianness, deletion markers, memo pointers, FPT block sizes, and opaque byte regions without external files.
  priority: must
  stability: evolving

- id: vfp_mcp.acceptance.phase1_safe_foundation
  statement: The Phase 1 test gate shall run from a Windows or Unix checkout without line-ending drift, require no external VFP root or IDE, and reject path escapes, original-application root candidates, live data bindings, external class locations, and incomplete source pairs before execution, compilation, or mutation.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.codec_evidence
  statement: Automated codec evidence shall cover golden parsing, malformed and truncated inputs, endianness, block-size variants, code-page behavior, hierarchy errors, opaque memo preservation, and deterministic pure results.
  priority: must
  stability: evolving

- id: vfp_mcp.acceptance.mutation_footprint
  statement: Every mutation class shall prove on disposable fixture copies that the intended semantic change is visible and all bytes outside the documented footprint are unchanged.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.native_edit_matrix
  statement: Before an edit class ships, its output shall be reparsed, opened, inspected, saved, reopened, and compiled in the originating VFP version, and only dependency-free synthetic fixtures may be run.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.version_compatibility
  statement: VFP 6 and VFP 9 shall each accept edits to their native fixtures, while cross-opening VFP 6 fixtures in VFP 9 is additional evidence and VFP 6 acceptance of VFP 9-only features is not a release gate.
  priority: must
  stability: stable

- id: vfp_mcp.acceptance.write_release_gates
  statement: Guarded writes shall remain disabled until timestamp handling, Windows pair replacement and recovery, representative native VFP acceptance, and synthetic opaque-memo preservation are resolved with recorded evidence.
  priority: must
  stability: evolving

- id: vfp_mcp.acceptance.structural_release_gates
  statement: Structural edits shall remain deferred until record-order and z-order behavior, new-record fidelity, reserved fields, UNIQUEID conventions, and container semantics are accepted in native VFP fixtures.
  priority: must
  stability: evolving

- id: vfp_mcp.acceptance.quality_gate
  statement: A release candidate shall compile with warnings as errors, be format-clean, pass unit, property, integration, malformed-input, safety, and protocol tests, and include required native acceptance records.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.acceptance.admit_fixture
  given:
    - a closed VFP-native fixture pair is delivered to the ignored fixture-drop directory
  when:
    - automated inventory and human review find only checklist-approved synthetic content and no live dependency
  then:
    - the pair may be promoted to the version-specific committed fixture directory
  covers:
    - vfp_mcp.acceptance.synthetic_native_fixtures
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.fixture_admission_protocol

- id: vfp_mcp.acceptance.reject_raw_application_fixture
  given:
    - an isolated intake pair contains application-derived code, names, paths, or class dependencies
  when:
    - it is considered for commit or execution
  then:
    - it remains quarantined and a purpose-built synthetic fixture is required instead
  covers:
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.raw_intake_quarantine
    - vfp_mcp.acceptance.fixture_admission_protocol

- id: vfp_mcp.acceptance.validate_evidence_bundle
  given:
    - a JSON native evidence record and Markdown signoff identify exact source and result pairs
  when:
    - the evidence bundle is validated
  then:
    - every required field, pair member, hash, native action, and review item must agree before the bundle is accepted
  covers:
    - vfp_mcp.acceptance.evidence_bundle_integrity

- id: vfp_mcp.acceptance.run_phase1_safe_suite
  given:
    - dependencies are available and no external VFP source root is configured
  when:
    - the Phase 1 safe suite runs with its fixed seed
  then:
    - formatting, warning-free compilation, unit, property, safety, protocol, integration, and strict specification checks all pass using only authorized isolated inputs
  covers:
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.phase1_safe_foundation
    - vfp_mcp.acceptance.deterministic_test_vectors

- id: vfp_mcp.acceptance.run_phase2_codec_suite
  given:
    - dependencies are available and only generated immutable pair bytes are configured
  when:
    - the Phase 2 physical codec suite runs with its fixed seed
  then:
    - golden, property, malformed-input, mixed-endian, encoding, fidelity, determinism, and strict specification checks pass without filesystem, IDE, or MCP effects
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.deterministic_test_vectors

- id: vfp_mcp.acceptance.accept_edit_class
  given:
    - an edit class passes automated semantic and byte-footprint checks on a disposable native fixture
  when:
    - the originating VFP version also opens, preserves, saves, reopens, and compiles the edited pair
  then:
    - that evidence may satisfy the version-specific gate for the edit class
  covers:
    - vfp_mcp.acceptance.mutation_footprint
    - vfp_mcp.acceptance.native_edit_matrix
    - vfp_mcp.acceptance.version_compatibility

- id: vfp_mcp.acceptance.keep_writes_disabled
  given:
    - one or more required write or structural evidence items remain unresolved
  when:
    - the server is built or launched
  then:
    - the affected capability remains unavailable even if self-parsing tests pass
  covers:
    - vfp_mcp.acceptance.write_release_gates
    - vfp_mcp.acceptance.structural_release_gates
```

## Verification

```spec-verification
- kind: guide_file
  target: docs/testing/fixture-authoring-checklist.md
  covers:
    - vfp_mcp.acceptance.synthetic_native_fixtures
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.native_edit_matrix
    - vfp_mcp.acceptance.version_compatibility
    - vfp_mcp.acceptance.admit_fixture
    - vfp_mcp.acceptance.accept_edit_class

- kind: guide_file
  target: docs/research/fixture-intake-investigation.md
  covers:
    - vfp_mcp.acceptance.raw_intake_quarantine
    - vfp_mcp.acceptance.reject_raw_application_fixture

- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.mutation_footprint
    - vfp_mcp.acceptance.write_release_gates
    - vfp_mcp.acceptance.structural_release_gates
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.keep_writes_disabled

- kind: guide_file
  target: docs/testing/fixture-lifecycle-and-evidence.md
  covers:
    - vfp_mcp.acceptance.raw_intake_quarantine
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.fixture_admission_protocol
    - vfp_mcp.acceptance.evidence_bundle_integrity
    - vfp_mcp.acceptance.version_native_handoff

- kind: guide_file
  target: docs/testing/vfp6-handoff.md
  covers:
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.version_native_handoff

- kind: guide_file
  target: docs/testing/vfp9-native-workflow.md
  covers:
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.version_native_handoff

- kind: guide_file
  target: docs/testing/phase-1-safe-suite.md
  covers:
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.phase1_safe_foundation
    - vfp_mcp.acceptance.run_phase1_safe_suite

- kind: guide_file
  target: docs/testing/phase-2-codec-suite.md
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.run_phase2_codec_suite

- kind: source_file
  target: lib/vfp_mcp/acceptance/fixture_admission.ex
  covers:
    - vfp_mcp.acceptance.raw_intake_quarantine
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.fixture_admission_protocol

- kind: source_file
  target: lib/vfp_mcp/acceptance/evidence.ex
  covers:
    - vfp_mcp.acceptance.evidence_bundle_integrity
    - vfp_mcp.acceptance.version_native_handoff

- kind: source_file
  target: lib/vfp_mcp/acceptance/fixture_safety.ex
  covers:
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.phase1_safe_foundation

- kind: test_file
  target: test/vfp_mcp/acceptance/fixture_admission_test.exs
  covers:
    - vfp_mcp.acceptance.raw_intake_quarantine
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.fixture_admission_protocol

- kind: test_file
  target: test/vfp_mcp/acceptance/evidence_test.exs
  covers:
    - vfp_mcp.acceptance.evidence_bundle_integrity
    - vfp_mcp.acceptance.validate_evidence_bundle

- kind: test_file
  target: test/vfp_mcp/test_support/pair_builder_test.exs
  covers:
    - vfp_mcp.acceptance.deterministic_test_vectors

- kind: test_file
  target: test/integration/phase_1_foundations_test.exs
  covers:
    - vfp_mcp.acceptance.no_live_dependencies
    - vfp_mcp.acceptance.fixture_review
    - vfp_mcp.acceptance.evidence_bundle_integrity
    - vfp_mcp.acceptance.deterministic_test_vectors
    - vfp_mcp.acceptance.phase1_safe_foundation
    - vfp_mcp.acceptance.run_phase1_safe_suite

- kind: source_file
  target: mix.exs
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.run_phase2_codec_suite

- kind: test_file
  target: test/integration/phase_2_physical_codec_test.exs
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.run_phase2_codec_suite

- kind: command
  target: 'cd "$OLDPWD" && mix phase2'
  execute: true
  covers:
    - vfp_mcp.acceptance.codec_evidence
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.run_phase2_codec_suite

- kind: command
  target: 'cd "$OLDPWD" && mix phase1'
  execute: true
  covers:
    - vfp_mcp.acceptance.quality_gate
    - vfp_mcp.acceptance.phase1_safe_foundation
    - vfp_mcp.acceptance.run_phase1_safe_suite
```
