# Fixture Lifecycle and Native Evidence

This document defines the admission states, evidence files, and version-specific
human responsibilities for synthetic Visual FoxPro fixtures.

<!--
specled covers:
- vfp_mcp.acceptance.raw_intake_quarantine
- vfp_mcp.acceptance.fixture_review
- vfp_mcp.acceptance.fixture_admission_protocol
- vfp_mcp.acceptance.evidence_bundle_integrity
- vfp_mcp.acceptance.version_native_handoff
-->

## Lifecycle

| State | Input location | Allowed operation | Required evidence | Next state |
|---|---|---|---|---|
| Dropped | `.vfp_mcp/fixture-drop/vfp6` or `vfp9` | Read-only automated inventory | Inventory JSON ID | Awaiting review or rejected |
| Awaiting review | Original dropped pair, unchanged | Human content and dependency review | Hash-bound Markdown checklist ID | Approved or rejected |
| Approved | Original dropped pair, unchanged | Hash-verified promotion only | Inventory and review IDs | Admitted |
| Admitted | `test/fixtures/vfp6` or `vfp9` | Automated read/parse or copy to an approved disposable root | Admission manifest ID and immutable member hashes | Remains admitted |
| Rejected | Original quarantine location | Review findings only | Rejection findings and prior evidence ID | Remains rejected; replace with a new synthetic pair |

Raw application-derived intake under `.vfp_mcp/intake` never enters this
lifecycle. It remains ignored, local, uncommitted, read-only, and unexecuted and
may be used only for isolated parser comparison. A rejection never authorizes
repair, execution, or mutation of the rejected artifact.

Promotion is authorized only after both automated inventory and human review
pass against the same hashes. `VfpMcp.Acceptance.FixtureAdmission` records this
authorization as pure data; the Phase 4 intake workflow performs the actual
hash-checked copy.

## Evidence bundle

Every fixture-authoring and native-edit scenario consists of:

1. one JSON record conforming to
   `priv/evidence/native-evidence.schema.json`;
2. one Markdown signoff based on
   `docs/testing/native-evidence-signoff-template.md`; and
3. the exact source pair and, for an edit, exact result pair named by the JSON.

The JSON records the schema version, evidence/scenario IDs, VFP and IDE
versions, operator, UTC timestamp, overall outcome, complete pair identities,
required actions, observations, and signoff filename. Every member has a byte
size and SHA-256; every pair has the complete-pair SHA-256 produced by
`PairSnapshot`.

The Markdown signoff repeats only the evidence ID and pair hashes needed to
bind the human review. It adds the reviewer, review timestamp, and required
checks. Any unchecked item, missing companion, malformed hash, omitted action,
failed action under an overall `pass`, mismatched signoff, or unknown outcome
causes validation failure.

Committed examples live under `test/fixtures/evidence/valid` and
`test/fixtures/evidence/invalid`. They contain invented names and placeholder
hashes only; they are protocol samples, not native acceptance evidence.

## VFP 9 responsibility

VFP 9 authoring and native acceptance are performed manually in the local VFP
9 IDE. The operator works only in a new synthetic workspace, closes the IDE
before hashing files, and returns pairs through the fixture-drop lifecycle.
Automation may prepare disposable copies and validate returned evidence but
must never drive the IDE, open a fixture in VFP, or claim the human actions.

## VFP 6 responsibility

VFP 6 authoring and native acceptance are performed by a human on an external
VFP 6 machine using the bounded package in `docs/testing/vfp6-handoff.md`.
Returned artifacts enter the VFP6 fixture-drop directory as untrusted input and
must pass the same automated and human reviews as VFP9 artifacts.

Local VFP9 opening of a VFP6 fixture is supplemental evidence only. It cannot
replace VFP6-native authoring or acceptance.
