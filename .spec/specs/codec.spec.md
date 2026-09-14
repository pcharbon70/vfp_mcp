# VFP Source Codec

The planned pure codec contract for parsing and surgically transforming VFP
form and class-library source pairs without losing designer-owned bytes.

## Intent

Make the physical DBF/FPT representation explicit, translate it into a semantic
document for queries, and retain enough raw information for lossless reads and
bounded future edits.

```spec-meta
id: vfp_mcp.codec
kind: module
status: active
summary: Fidelity-preserving DBF, FPT, text, property, method, and hierarchy codec.
surface:
  - docs/research/architecture-and-format-research.md
  - docs/research/progress-to-date.md
  - docs/architecture.md
  - docs/components.md
  - docs/contracts/codec-domain.md
  - docs/contracts/physical-codec.md
  - docs/contracts/semantic-codec.md
  - lib/vfp_mcp/codec.ex
  - lib/vfp_mcp/codec/dbf.ex
  - lib/vfp_mcp/codec/encoding.ex
  - lib/vfp_mcp/codec/fpt.ex
  - lib/vfp_mcp/codec/physical_summary.ex
  - lib/vfp_mcp/codec/properties.ex
  - lib/vfp_mcp/codec/methods.ex
  - lib/vfp_mcp/codec/semantic_text.ex
  - lib/vfp_mcp/codec/semantic.ex
  - lib/vfp_mcp/codec/tree.ex
  - lib/vfp_mcp/source/path.ex
  - lib/vfp_mcp/validate.ex
  - lib/vfp_mcp/document.ex
  - lib/vfp_mcp/edit_plan.ex
  - lib/vfp_mcp/finding.ex
  - lib/vfp_mcp/limits.ex
  - lib/vfp_mcp/source/pair_snapshot.ex
  - lib/vfp_mcp/source/span.ex
  - test/vfp_mcp/codec_contract_test.exs
  - test/vfp_mcp/codec/dbf_test.exs
  - test/vfp_mcp/codec/encoding_test.exs
  - test/vfp_mcp/codec/fpt_test.exs
  - test/vfp_mcp/codec/physical_codec_test.exs
  - test/vfp_mcp/codec/properties_test.exs
  - test/vfp_mcp/codec/methods_test.exs
  - test/vfp_mcp/codec/semantic_test.exs
  - test/vfp_mcp/codec/tree_test.exs
  - test/vfp_mcp/source/path_test.exs
  - test/vfp_mcp/validate_test.exs
  - test/integration/phase_2_physical_codec_test.exs
  - test/vfp_mcp/limits_test.exs
decisions:
  - vfp_mcp.custom_vfp_codec
```

## Requirements

```spec-requirements
- id: vfp_mcp.codec.dbf_structure
  statement: The codec shall parse DBF record count, header length, record length, code-page byte, field descriptors, fixed-width values, and active or deleted record markers from their documented offsets.
  priority: must
  stability: stable

- id: vfp_mcp.codec.memo_pointer
  statement: The codec shall interpret each VFP memo pointer as a four-byte little-endian binary block number with zero representing an empty memo.
  priority: must
  stability: stable

- id: vfp_mcp.codec.fpt_structure
  statement: The codec shall read the FPT next-free pointer and block size as big-endian values, treat a stored block size of zero as 512, and bounds-check every resolved memo block.
  priority: must
  stability: stable

- id: vfp_mcp.codec.memo_block
  statement: The codec shall parse each FPT block as a big-endian type and length followed by bounded payload bytes and shall preserve the source block type when planning a replacement.
  priority: must
  stability: stable

- id: vfp_mcp.codec.lossless_encoding
  statement: The codec shall derive text encoding from source metadata, expose UTF-8 internally, support strict Windows-1252 writes initially, and reject any write that cannot round-trip without replacement.
  priority: must
  stability: evolving

- id: vfp_mcp.codec.raw_fidelity
  statement: The parsed document shall retain raw headers, records, memo pointers, memo payloads, reserved fields, deleted records, OLE data, and unknown bytes without normalization.
  priority: must
  stability: stable

- id: vfp_mcp.codec.property_edit_scope
  statement: Property parsing shall preserve ordering, line endings, spelling, whitespace, expressions, and unsupported literals so a planned edit replaces only explicitly targeted property lines.
  priority: must
  stability: stable

- id: vfp_mcp.codec.method_edit_scope
  statement: Method parsing shall preserve source verbatim and identify PROCEDURE through ENDPROC blocks so a planned edit can target one named event or an exact guarded match without replacing sibling methods.
  priority: must
  stability: stable

- id: vfp_mcp.codec.semantic_document
  statement: The codec shall produce source-pair identity, version and encoding metadata, records, objects, data-environment entries, full-path indexes, and validation findings while retaining the physical model.
  priority: must
  stability: evolving

- id: vfp_mcp.codec.hierarchy_integrity
  statement: Hierarchy construction shall use OBJNAME and PARENT, preserve parent-relative geometry, assign unambiguous full control paths, and report duplicate siblings, missing parents, and cycles.
  priority: must
  stability: stable

- id: vfp_mcp.codec.pure_planning
  statement: Parsing, rendering, validation, and edit planning shall be deterministic pure transformations with no file-system or MCP side effects.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.codec.parse_mixed_endian_pair
  given:
    - a supported DBF and FPT source pair with binary memo pointers
  when:
    - the pair is parsed
  then:
    - little-endian DBF values and big-endian FPT values resolve to bounded records and memo payloads
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block

- id: vfp_mcp.codec.reject_invalid_memo
  given:
    - a memo pointer or declared payload extends outside its companion file
  when:
    - the pair is parsed or validated
  then:
    - a structured finding is returned and no guessed or partial payload is exposed as valid
  covers:
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.semantic_document

- id: vfp_mcp.codec.reject_unrepresentable_text
  given:
    - a planned text edit contains characters not representable by the source code page
  when:
    - the edit is encoded
  then:
    - planning fails without producing replacement bytes
  covers:
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.pure_planning

- id: vfp_mcp.codec.plan_named_method_edit
  given:
    - one object METHODS memo contains multiple procedure blocks
  when:
    - an edit targets one named event
  then:
    - the plan changes only that event source and preserves sibling blocks and unrelated bytes
  covers:
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.method_edit_scope
    - vfp_mcp.codec.pure_planning
```

## Verification

```spec-verification
- kind: guide_file
  target: docs/research/architecture-and-format-research.md
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.parse_mixed_endian_pair

- kind: guide_file
  target: docs/research/progress-to-date.md
  covers:
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.property_edit_scope
    - vfp_mcp.codec.method_edit_scope
    - vfp_mcp.codec.reject_unrepresentable_text
    - vfp_mcp.codec.plan_named_method_edit

- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.reject_invalid_memo

- kind: guide_file
  target: docs/components.md
  covers:
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec.ex
  covers:
    - vfp_mcp.codec.pure_planning

- kind: guide_file
  target: docs/contracts/physical-codec.md
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/dbf.ex
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/dbf_test.exs
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/fpt.ex
  covers:
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/fpt_test.exs
  covers:
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning
    - vfp_mcp.codec.parse_mixed_endian_pair
    - vfp_mcp.codec.reject_invalid_memo

- kind: source_file
  target: lib/vfp_mcp/codec/encoding.ex
  covers:
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning
    - vfp_mcp.codec.reject_unrepresentable_text

- kind: source_file
  target: lib/vfp_mcp/codec/physical_summary.ex
  covers:
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: guide_file
  target: docs/contracts/semantic-codec.md
  covers:
    - vfp_mcp.codec.property_edit_scope
    - vfp_mcp.codec.method_edit_scope
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/semantic.ex
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/properties.ex
  covers:
    - vfp_mcp.codec.property_edit_scope
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/methods.ex
  covers:
    - vfp_mcp.codec.method_edit_scope
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/codec/tree.ex
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/source/path.ex
  covers:
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: source_file
  target: lib/vfp_mcp/validate.ex
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/encoding_test.exs
  covers:
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning
    - vfp_mcp.codec.reject_unrepresentable_text

- kind: test_file
  target: test/vfp_mcp/codec/physical_codec_test.exs
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.pure_planning
    - vfp_mcp.codec.parse_mixed_endian_pair
    - vfp_mcp.codec.reject_invalid_memo

- kind: test_file
  target: test/vfp_mcp/codec/semantic_test.exs
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/properties_test.exs
  covers:
    - vfp_mcp.codec.property_edit_scope
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/methods_test.exs
  covers:
    - vfp_mcp.codec.method_edit_scope
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/codec/tree_test.exs
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/source/path_test.exs
  covers:
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/validate_test.exs
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.hierarchy_integrity
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/integration/phase_2_physical_codec_test.exs
  covers:
    - vfp_mcp.codec.dbf_structure
    - vfp_mcp.codec.memo_pointer
    - vfp_mcp.codec.fpt_structure
    - vfp_mcp.codec.memo_block
    - vfp_mcp.codec.lossless_encoding
    - vfp_mcp.codec.raw_fidelity
    - vfp_mcp.codec.pure_planning
    - vfp_mcp.codec.parse_mixed_endian_pair
    - vfp_mcp.codec.reject_invalid_memo

- kind: test_file
  target: test/vfp_mcp/codec_contract_test.exs
  covers:
    - vfp_mcp.codec.semantic_document
    - vfp_mcp.codec.pure_planning

- kind: test_file
  target: test/vfp_mcp/limits_test.exs
  covers:
    - vfp_mcp.codec.pure_planning
```
