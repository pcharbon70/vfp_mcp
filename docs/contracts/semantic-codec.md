# Semantic VFP Source Codec

<!--
specled covers:
- vfp_mcp.codec.property_edit_scope
- vfp_mcp.codec.method_edit_scope
- vfp_mcp.codec.semantic_document
- vfp_mcp.codec.hierarchy_integrity
- vfp_mcp.codec.raw_fidelity
- vfp_mcp.codec.pure_planning
- vfp_mcp.read.full_path_identity
- vfp_mcp.read.validation_findings
- vfp_mcp.read.source_fidelity
-->

The semantic codec reads only decoded type-1 memo views produced by the
physical codec. Original FPT payload bytes remain authoritative. Parsing is a
pure transformation and neither opens identity paths nor renders replacement
content.

## Property memo model

`VfpMcp.Codec.Properties` splits the original bytes without changing line
endings. It recognizes unambiguous `Name = Literal` assignments and preserves
the exact name spelling, whitespace around `=`, raw literal, complete line,
source-byte spans, and UTF-8 text spans.

The initial semantic literal set is:

- doubled-quote VFP strings;
- `.T.` and `.F.` booleans;
- signed integers and decimal spellings;
- `.NULL.`;
- `{^yyyy-mm-dd}` dates; and
- `{^yyyy-mm-dd hh:mm:ss}` datetimes.

Decimals retain their source spelling as `{:decimal, text}` so parsing does not
introduce floating-point rounding. Dates and datetimes are tagged tuples around
Elixir calendar values. Comments, blank lines, continuations, expressions,
unknown constructs, malformed strings, and duplicate property names remain
verbatim. Their assignment-level eligibility explains why they cannot be a
typed edit target.

## Method memo model

`VfpMcp.Codec.Methods` recognizes case-insensitive `PROCEDURE name` and
`ENDPROC` markers only at the beginning of a non-comment line. Each complete
method retains its declared name, exact signature suffix, declaration bytes,
decoded body, body bytes, terminator bytes, complete raw block, and byte/text
spans.

Marker-like phrases in strings, ordinary code, `*` comments, and `&&` comment
lines do not form boundaries. Duplicate names, nested procedures, unmatched
terminators, and unterminated procedures produce stable findings. The full memo
remains inspectable, but ambiguous named methods are ineligible for targeting.

## Byte and text correspondence

Every source span is calculated from the original Windows-1252 bytes. Text
spans are calculated independently over the decoded UTF-8 representation.
Consequently an extended character can increase a later UTF-8 offset without
shifting its source-byte offset. Both property and method memo structures retain
the original payload, decoded text, detected line-ending style, and parse index;
reading semantic values never re-encodes the memo.

## Hierarchy and paths

`VfpMcp.Codec.Tree` resolves a non-empty `PARENT` against a case-insensitive
global `OBJNAME` index. It does not use row adjacency, so reordering records
cannot change an unambiguous graph. Empty parents form roots. Missing,
multiply-resolved, self, cyclic, excessive-depth, and non-container parents
remain inspectable findings and do not receive guessed paths.

Display paths retain source spelling and join percent-escaped UTF-8 segments
with `/`. Slash, percent, space, and extended characters therefore round-trip
without ambiguity. Lookup decodes each segment, applies the same lowercase case
policy used during construction, and re-encodes it. Exact duplicate siblings
and case-colliding paths are removed from the lookup index; no first-record-wins
behavior is permitted.

The initial compatible container base classes are `formset`, `form`,
`pageframe`, `page`, `grid`, `column`, `container`, `optiongroup`,
`commandgroup`, and `toolbar`.

## Validation and eligibility

`VfpMcp.Validate` owns deterministic finding order: member and physical offset,
then rule code, then semantic identity. The Phase 3 rule matrix publishes a
stable severity, impact, and scope for semantic identity, compatibility,
property, method, and hierarchy findings. Fatal physical findings still return
an error with no document. Successful documents remain inspectable; warnings
preserve content, while mutation-blocking errors feed explicit document and
per-object eligibility values.

| Rule code | Severity | Impact | Scope |
|---|---|---|---|
| `semantic_identity_field_missing` | error | mutation blocked | schema |
| `semantic_identity_field_ambiguous` | error | mutation blocked | schema |
| `semantic_identity_value_unavailable` | error | mutation blocked | object |
| `semantic_identity_value_ambiguous` | error | mutation blocked | object |
| `semantic_vfp_version_undeclared` | info | informational | pair |
| `semantic_dbf_format_unsupported` | error | mutation blocked | pair |
| `property_duplicate_assignment` | error | mutation blocked | object |
| `property_malformed_string` | error | mutation blocked | object |
| `property_memo_ambiguous` | error | mutation blocked | object |
| `property_unsupported_literal` | warning | preserved | line |
| `property_continuation` | warning | preserved | line |
| `property_unsupported_line` | warning | preserved | line |
| `method_duplicate_name` | error | mutation blocked | object |
| `method_nested_procedure` | error | mutation blocked | object |
| `method_unmatched_endproc` | error | mutation blocked | object |
| `method_missing_endproc` | error | mutation blocked | object |
| `method_memo_ambiguous` | error | mutation blocked | object |
| `hierarchy_object_name_missing` | error | mutation blocked | object |
| `hierarchy_parent_missing` | error | mutation blocked | object |
| `hierarchy_parent_ambiguous` | error | mutation blocked | object |
| `hierarchy_self_parent` | error | mutation blocked | object |
| `hierarchy_cycle` | error | mutation blocked | objects |
| `hierarchy_incompatible_parent` | error | mutation blocked | object |
| `limit_hierarchy_depth_exceeded` | error | mutation blocked | object |
| `hierarchy_duplicate_sibling` | error | mutation blocked | objects |
| `hierarchy_path_canonicalization_collision` | error | mutation blocked | objects |

## Phase 3 evidence

The fixed-seed Phase 3 suite builds complete synthetic form and class-library
pairs in memory and compares semantic manifests, physical provenance, raw
record and memo bytes, invalid findings, concurrent results, and content-safe
canonical summaries. It also verifies that the pure codec ignores identity
paths and produces no filesystem, process, clock, locale, or protocol effect.
