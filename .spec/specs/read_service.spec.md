# Read Service

The planned discovery, parsing, caching, querying, and validation behavior used
by every read-only MCP workflow.

## Intent

Turn VFP source pairs into bounded, LLM-oriented trees, details, code, binding,
search, and validation results without treating a cache as authoritative.

```spec-meta
id: vfp_mcp.read_service
kind: service
status: planned
summary: Confined read pipeline over immutable source-pair snapshots.
surface:
  - docs/architecture.md
  - docs/components.md
  - docs/contracts/codec-domain.md
  - docs/contracts/physical-codec.md
  - docs/contracts/semantic-codec.md
  - lib/vfp_mcp/codec.ex
  - lib/vfp_mcp/codec/semantic.ex
  - lib/vfp_mcp/codec/tree.ex
  - lib/vfp_mcp/source/path.ex
  - lib/vfp_mcp/validate.ex
  - lib/vfp_mcp/source/pair_snapshot.ex
  - test/vfp_mcp/codec_contract_test.exs
  - test/vfp_mcp/codec/physical_codec_test.exs
  - test/vfp_mcp/codec/semantic_test.exs
  - test/vfp_mcp/codec/tree_test.exs
  - test/vfp_mcp/source/path_test.exs
  - test/vfp_mcp/validate_test.exs
decisions:
  - vfp_mcp.source_access_boundary
  - vfp_mcp.custom_vfp_codec
```

## Requirements

```spec-requirements
- id: vfp_mcp.read.discovery_pairs
  statement: Discovery shall find SCX/SCT and VCX/VCT companions case-insensitively under the configured root, deduplicate canonical paths, and report missing companions instead of inventing a partial source.
  priority: must
  stability: stable

- id: vfp_mcp.read.immutable_snapshot
  statement: Each read shall operate on immutable bytes associated with a complete source-pair identity including canonical paths, sizes, modification times, and a cryptographic pair hash.
  priority: must
  stability: stable

- id: vfp_mcp.read.cache_validation
  statement: Cached documents may accelerate reads only after current file identity is checked, and cache entries shall be invalidated after verified writes or external changes.
  priority: must
  stability: stable

- id: vfp_mcp.read.query_shapes
  statement: Query operations shall expose source inventories, form overviews, control trees, control details, code locations, named control code, source search, data-environment metadata, and validation findings.
  priority: must
  stability: stable

- id: vfp_mcp.read.full_path_identity
  statement: Control lookup shall use canonical full hierarchy paths and shall reject ambiguous shorthand rather than selecting an arbitrary duplicate name.
  priority: must
  stability: stable

- id: vfp_mcp.read.external_references
  statement: Reads may report external CLASSLOC and data-binding path text but shall not traverse those references or open their target data.
  priority: must
  stability: stable

- id: vfp_mcp.read.validation_findings
  statement: Validation shall distinguish fatal container or bounds errors from source warnings such as missing parents, duplicate sibling names, unsupported encodings, mixed versions, and external references.
  priority: must
  stability: evolving

- id: vfp_mcp.read.bounded_results
  statement: Every result shall enforce configured text, match, file, depth, and byte limits and shall indicate truncation or continuation without silently omitting it.
  priority: must
  stability: stable

- id: vfp_mcp.read.source_fidelity
  statement: Read operations shall not normalize, rewrite, compile, execute, or otherwise mutate source files.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.read.missing_companion
  given:
    - discovery finds one member of a supported source pair
  when:
    - its companion cannot be resolved case-insensitively under the root
  then:
    - discovery returns a missing-companion finding and does not parse a partial pair
  covers:
    - vfp_mcp.read.discovery_pairs

- id: vfp_mcp.read.changed_after_cache
  given:
    - a parsed source document is cached
  when:
    - either source file has a different current identity
  then:
    - the cache entry is not returned as current and fresh bytes are parsed
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.cache_validation

- id: vfp_mcp.read.ambiguous_control
  given:
    - separate containers contain controls with the same OBJNAME
  when:
    - a query supplies a non-unique shorthand name
  then:
    - the query returns an ambiguity error with candidate full paths
  covers:
    - vfp_mcp.read.full_path_identity

- id: vfp_mcp.read.external_class_reference
  given:
    - a source record contains a CLASSLOC outside the configured root
  when:
    - the source is inspected
  then:
    - the reference text and finding are returned without opening the external target
  covers:
    - vfp_mcp.read.external_references
    - vfp_mcp.read.validation_findings

- id: vfp_mcp.read.truncated_result
  given:
    - a search or source response exceeds a configured output limit
  when:
    - the result is shaped
  then:
    - the response remains within the limit and explicitly reports truncation or continuation data
  covers:
    - vfp_mcp.read.bounded_results
```

## Verification

```spec-verification
- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.cache_validation
    - vfp_mcp.read.full_path_identity
    - vfp_mcp.read.bounded_results
    - vfp_mcp.read.source_fidelity
    - vfp_mcp.read.changed_after_cache
    - vfp_mcp.read.ambiguous_control
    - vfp_mcp.read.truncated_result

- kind: guide_file
  target: docs/components.md
  covers:
    - vfp_mcp.read.discovery_pairs
    - vfp_mcp.read.query_shapes
    - vfp_mcp.read.external_references
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.missing_companion
    - vfp_mcp.read.external_class_reference

- kind: source_file
  target: lib/vfp_mcp/source/pair_snapshot.ex
  covers:
    - vfp_mcp.read.immutable_snapshot

- kind: source_file
  target: lib/vfp_mcp/codec.ex
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: source_file
  target: lib/vfp_mcp/codec/semantic.ex
  covers:
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: guide_file
  target: docs/contracts/physical-codec.md
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: test_file
  target: test/vfp_mcp/codec/physical_codec_test.exs
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: guide_file
  target: docs/contracts/semantic-codec.md
  covers:
    - vfp_mcp.read.full_path_identity
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: test_file
  target: test/vfp_mcp/codec/semantic_test.exs
  covers:
    - vfp_mcp.read.immutable_snapshot
    - vfp_mcp.read.validation_findings
    - vfp_mcp.read.source_fidelity

- kind: source_file
  target: lib/vfp_mcp/codec/tree.ex
  covers:
    - vfp_mcp.read.full_path_identity
    - vfp_mcp.read.validation_findings

- kind: source_file
  target: lib/vfp_mcp/source/path.ex
  covers:
    - vfp_mcp.read.full_path_identity

- kind: source_file
  target: lib/vfp_mcp/validate.ex
  covers:
    - vfp_mcp.read.validation_findings

- kind: test_file
  target: test/vfp_mcp/codec/tree_test.exs
  covers:
    - vfp_mcp.read.full_path_identity
    - vfp_mcp.read.validation_findings

- kind: test_file
  target: test/vfp_mcp/source/path_test.exs
  covers:
    - vfp_mcp.read.full_path_identity

- kind: test_file
  target: test/vfp_mcp/validate_test.exs
  covers:
    - vfp_mcp.read.validation_findings

- kind: test_file
  target: test/vfp_mcp/codec_contract_test.exs
  covers:
    - vfp_mcp.read.immutable_snapshot
```
