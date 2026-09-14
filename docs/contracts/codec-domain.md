# Codec and Domain Contract

This document fixes the codec interfaces and data ownership rules. Physical
decoding and semantic record/object construction are implemented; edit
planning remains a later phase.

<!--
specled covers:
- vfp_mcp.codec.semantic_document
- vfp_mcp.codec.pure_planning
- vfp_mcp.read.immutable_snapshot
-->

## Parse boundary

```elixir
VfpMcp.Codec.parse_pair(pair_snapshot, limits: limits)
# => {:ok, %VfpMcp.Document{findings: non_fatal_findings}}
#  | {:error, [%VfpMcp.Finding{severity: :fatal}]}
```

The caller supplies both immutable members in `PairSnapshot`; the codec never
opens their optional identity paths. A success owns warnings and
mutation-blocking findings inside the document. An error returns only fatal
findings and must not expose guessed semantic content as valid.

Physical decoding is documented in
[the physical codec contract](physical-codec.md). The semantic stage classifies
every physical row, extracts only unambiguous known identity fields, and creates
object and data-environment views. Dedicated semantic stages add property,
method, and hierarchy indexes without replacing physical content.

## Source identity and provenance

`PairSnapshot` contains DBF and FPT bytes plus:

- logical source ID and pair kind (`:scx` or `:vcx`);
- optional declared compatibility target (`6` or `9`);
- optional caller-supplied canonical paths and modification timestamps;
- individual member roles, sizes, and SHA-256 hashes; and
- a versioned SHA-256 digest over the complete ordered pair bytes.

Optional member paths, when supplied, must have companion extensions matching
the declared `:scx` (`.scx`/`.sct`) or `:vcx` (`.vcx`/`.vct`) pair kind. A
contradiction fails before semantic values are returned.

Semantic values retain `Span` and `MemoRef` links to member, record, field,
pointer, block, and payload offsets. `Document` owns the physical model,
schema, records, objects, tree, path index, encoding/version metadata, and
non-fatal findings. Unknown fields and bytes stay in the physical model rather
than being normalized into semantic values. `semantic_records` has one stable
entry per physical row, including deleted, bookend, comment, data-environment,
and unknown rows. Each semantic value retains its field or memo payload span
plus the originating memo pointer when applicable.

Successful documents are explicitly `:inspectable`. Their independent
`edit_eligibility` is either `:eligible` or `{:blocked, finding_codes}`. A
bounded semantic ambiguity can therefore remain readable without being
mistaken for a safe mutation target.

Hierarchy construction resolves `PARENT` by unambiguous semantic identity,
builds escaped display paths, and stores only case-canonical, collision-free
keys in `path_index`. `tree` contains record-index roots and children only for
addressable objects. Invalid edges and ambiguous paths remain on the source
objects and in findings, not in the target index.

## Finding taxonomy

| Severity | Impact | Meaning |
|---|---|---|
| `fatal` | `unreadable` | Physical boundaries or identity are not trustworthy; return an error tuple |
| `error` | `mutation_blocked` | Bounded content may be inspected, but edit planning is unsafe |
| `warning` | `preserved` | Unusual or unsupported bounded content is retained unchanged |
| `info` | `informational` | Compatibility or explanatory note |

Every finding has a stable atom code, safe bounded message, optional physical
or semantic location, and a small evidence map. Callers act on codes, severity,
and impact rather than parsing message text.

## Resource limits

| Limit | Default | Stable exceeded code |
|---|---:|---|
| Pair member bytes | 64 MiB | `limit_member_bytes_exceeded` |
| Records | 100,000 | `limit_records_exceeded` |
| Fields | 256 | `limit_fields_exceeded` |
| One memo payload | 16 MiB | `limit_memo_payload_bytes_exceeded` |
| Memo blocks | 100,000 | `limit_memo_blocks_exceeded` |
| Findings | 1,000 | `limit_findings_exceeded` |
| Hierarchy depth | 256 | `limit_hierarchy_depth_exceeded` |
| Parsed text bytes | 16 MiB | `limit_parsed_text_bytes_exceeded` |

Overrides must use known keys and positive integers. Each parser or traversal
checks its corresponding limit before slicing, allocating, accumulating, or
descending. Phase 1 enforces member limits at the public parse boundary; later
phases must enforce their specific limits before their operations.

## Pure edit-plan result

Future planner signatures are:

```elixir
VfpMcp.Edit.Properties.plan(document, object_path, property_change, options)
VfpMcp.Edit.Methods.plan(document, object_path, method_name, method_change, options)

# both return
{:ok, %VfpMcp.EditPlan{}} | {:error, [%VfpMcp.Finding{}]}
```

`EditPlan` is bound to the complete `PairIdentity` and contains only exact DBF
patches, aligned FPT appends, expected DBF/FPT footprint spans, non-fatal
findings, and a semantic postcondition. It contains no path-writing authority,
lock, backup, journal, rollback, MCP type, callback, or process reference.

Example property postcondition:

```elixir
%VfpMcp.EditPlan.Postcondition{
  kind: :property,
  target: %{object_path: "frmBasic/cmdApply", property: "Caption"},
  expected: "Run"
}
```

Example method postcondition:

```elixir
%VfpMcp.EditPlan.Postcondition{
  kind: :method,
  target: %{object_path: "frmBasic/cmdApply", method: "Click"},
  expected: %{source_sha256: "<lowercase SHA-256>"}
}
```
