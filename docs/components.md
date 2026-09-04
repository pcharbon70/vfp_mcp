# VFP MCP Component Design

**Status:** Draft for review  
**Companion:** [Architecture](architecture.md)

## 1. Component map

```text
VfpMcp.Application
  +-- VfpMcp.Server
  |     +-- ToolRegistry
  |     +-- Output
  +-- VfpMcp.Discovery
  +-- VfpMcp.Query
  +-- VfpMcp.Cache
  +-- VfpMcp.Writer
  |     +-- Lock
  |     +-- Backup
  |     +-- Journal
  |     +-- PairCommit
  +-- VfpMcp.Edit
  +-- VfpMcp.Validate
  +-- VfpMcp.Codec
        +-- Dbf
        +-- Fpt
        +-- Scx
        +-- Properties
        +-- Methods
        +-- Tree
        +-- Encoding
```

Names are provisional, but the boundaries are intentional. Dependencies flow
inward from protocol and I/O toward pure domain and codec modules.

## 2. OTP supervision

`VfpMcp.Application` starts:

1. configuration validation (`--root`, `--vfp-version`, optional `--write`);
2. a task supervisor for bounded read requests;
3. the parsed-document cache;
4. the single mutation writer;
5. the MCP transport/session supervisor.

Codec, validation, query, and edit-planning modules are pure libraries and do
not need processes.

## 3. Protocol components

### `VfpMcp.Server`

Owns MCP integration and delegates all domain work.

Responsibilities:

- register tools, resources, prompts, and their JSON Schemas;
- validate protocol-level inputs;
- attach accurate read/destructive/idempotent annotations;
- translate domain results and errors into MCP result content;
- enforce response-size limits and pagination;
- contain request failures without terminating the server.

It must not parse DBF/FPT bytes or perform direct filesystem writes.

### `VfpMcp.ToolRegistry`

Defines tool metadata separately from handler implementation. Initial groups:

- discovery and comprehension;
- code and property reads;
- validation and diffing;
- guarded property and code mutations;
- later structural mutations.

Schemas should be reusable in contract tests so advertised schemas and handler
expectations cannot drift.

### `VfpMcp.Output`

Shapes domain results for model consumption:

- path-addressed trees;
- concise overviews;
- event inventories;
- textual layout sketches;
- structured semantic diffs;
- paginated search results.

It keeps presentation logic out of the codec and query services.

## 4. Project and query components

### `VfpMcp.PathPolicy`

Canonicalizes user paths, resolves pair extensions case-insensitively, rejects
traversal or aliases that escape the configured root, and applies configured
directory exclusions. External `CLASSLOC` values are reported but not followed.

Suggested interface:

```elixir
resolve_pair(root, requested_path) :: {:ok, Pair.t()} | {:error, reason}
```

### `VfpMcp.Discovery`

Finds SCX/SCT and VCX/VCT pairs beneath the authorized root. It reports missing
companions and duplicate/case-conflicting candidates rather than guessing.

### `VfpMcp.Query`

Provides storage-independent use cases:

- form overview;
- control tree and detail lookup;
- class ancestry;
- data-environment and binding summaries;
- method inventory and retrieval;
- scoped project search;
- layout rendering input.

It consumes parsed documents and returns domain values, not MCP payloads.

### `VfpMcp.Cache`

Stores immutable parsed documents keyed by canonical pair identity and source
metadata or hashes. It supports lookup, replace, invalidate-pair, and clear.
No mutation is ever planned from an unverified cached document.

## 5. Codec components

### `VfpMcp.Codec.Dbf`

Parses DBF headers, field descriptors, fixed records, deletion flags, and raw
field slices. It retains offsets needed for exact patch planning.

It validates all lengths before slicing and never assumes a fixed SCX schema.

### `VfpMcp.Codec.Fpt`

Parses the memo header and reads typed memo blocks with explicit endianness. It
plans aligned append operations and next-free-block updates without mutating
the original byte sequence.

### `VfpMcp.Codec.Encoding`

Maps DBF code-page identifiers to encoders and decoders. Modified text must
round-trip exactly. Unknown or lossy encodings produce an error for writes.

### `VfpMcp.Codec.Scx`

Combines DBF records and FPT memos into the semantic document. It classifies
known textual memo fields while preserving unknown/binary content as opaque
references and bytes.

### `VfpMcp.Codec.Properties`

Parses the line-oriented VFP property sheet conservatively. It records both
semantic assignments and original spans/formatting.

Initial rendering supports strings, booleans, integers, decimals, `.NULL.`, and
explicitly tagged dates/datetimes. Unsupported expressions are preserved but
cannot be rewritten through typed setters.

### `VfpMcp.Codec.Methods`

Indexes `PROCEDURE ... ENDPROC` method blocks while retaining verbatim source,
line endings, and sibling blocks. It supports exact event replacement and
guarded literal patch planning without pretending to be a full VFP parser.

### `VfpMcp.Codec.Tree`

Builds and validates containment from `OBJNAME` and `PARENT`, detects ambiguous
or invalid relationships, and creates canonical paths. Path construction and
lookup must share one escaping/case policy.

## 6. Domain types

Suggested core structures:

```text
Pair
  dbf_path, fpt_path, kind, identity

Document
  pair, schema, records, objects, tree, path_index, findings

Object
  record_index, identity fields, raw fields, properties, methods, memo refs

Edit
  operation, target path, preconditions, requested value

EditPlan
  source identity, memo appends, DBF patches, expected footprint, postcondition

Diff
  object path, field/property/method, before, after, physical footprint

Finding
  severity, code, location, message, evidence
```

Domain types should retain enough physical provenance to explain validation
failures and prove the exact footprint of a write.

## 7. Validation component

### `VfpMcp.Validate`

Runs named rules and produces stable finding codes. Validation must distinguish:

- fatal parsing errors;
- errors that block mutation;
- warnings about unusual but preserved content;
- informational compatibility notes.

Rules are deterministic and independently testable. Post-write validation also
receives the edit plan so it can verify the expected physical footprint and
semantic postcondition.

## 8. Edit-planning components

### `VfpMcp.Edit.Properties`

Locates one path-addressed object, checks expected old values, renders supported
VFP literals, and plans replacement of only its `PROPERTIES` memo.

### `VfpMcp.Edit.Methods`

Locates one method block or guarded literal match, checks expected counts,
preserves unrelated blocks, plans the `METHODS` append, and clears `OBJCODE`.

### `VfpMcp.Edit.Structure`

Reserved for Phase 3. It must remain disabled until record conventions,
bookends, `UNIQUEID`, timestamp behavior, subtree deletion, and Z-order have
passed VFP-authored comparison tests.

All planners return data; they never write files.

## 9. Mutation infrastructure

### `VfpMcp.Writer`

A single GenServer serializes mutations. It orchestrates fresh parsing,
preconditions, prepare/apply plan IDs, lock acquisition, backup, planning,
commit, reparsing, validation, journaling, cache invalidation, and response
construction. Plans expire and become invalid when either source file hash
changes.

The GenServer is a coordinator, not the home of codec or editing logic.

### `VfpMcp.Lock`

Acquires exclusive access to both files in deterministic order and verifies
their identities before commit. The Windows implementation requires an
acceptance test against files actually open in VFP 9.

### `VfpMcp.Backup`

Creates, lists, verifies, and restores paired backups. A manifest records source
paths, sizes, hashes, timestamps, and operation identity. Restore is itself an
audited, validated mutation.

### `VfpMcp.Journal`

Records lifecycle states such as prepared, files-written, validated, committed,
failed, and restored. Its primary job is recovery and auditability, not storage
of arbitrary full source code.

### `VfpMcp.PairCommit`

Owns the platform-specific durable-write protocol for the DBF/FPT pair. It
materializes files, flushes them, replaces them in the safest proven order,
and exposes interruption points for fault-injection testing.

## 10. Initial MCP surface

The recommended first release exposes a deliberately smaller surface than the
full research catalog:

| Tool | Purpose |
|---|---|
| `list_sources` | Discover valid form and class-library pairs. |
| `get_form_overview` | Summarize form metadata and contents. |
| `get_control_tree` | Return canonical, path-addressed containment. |
| `get_control_details` | Return one object's properties and event inventory. |
| `list_code_locations` | Inventory objects and method blocks containing code. |
| `get_control_code` | Retrieve verbatim method source. |
| `search_sources` | Search code or properties with bounded context. |
| `get_dataenvironment` | Describe declared cursors, relations, and bindings. |
| `validate_source` | Return stable validation findings. |

After acceptance gates, add:

| Tool | Purpose |
|---|---|
| `prepare_edit` | Validate one requested SCX edit and return an expiring plan ID, source hash, and diff. |
| `apply_edit` | Apply an unchanged prepared plan after hash and write-mode checks. |
| `set_control_properties` | Apply typed, preconditioned property changes. |
| `set_control_method` | Replace one event block. |
| `patch_control_code` | Apply guarded literal replacement. |
| `diff_source` | Compare current state with a backup or supplied pair. |
| `list_backups` / `restore_backup` | Make recovery explicit. |

Write tools operate on one existing SCX form/control target per transaction.
VCX records, data-environment records, comment/bookend records, OLE controls,
and unknown record types are read-only in the first release.

Combining similar read operations keeps tool selection understandable. More
specialized convenience tools can be introduced from observed workflows.

`set_control_properties`, `set_control_method`, and `patch_control_code` are
domain operations used by `prepare_edit`; they do not bypass the prepare/apply
transaction boundary.

## 11. Error model

Domain errors use stable categories:

- `invalid_path` / `outside_root`;
- `pair_incomplete` / `pair_changed` / `pair_locked`;
- `unsupported_format` / `unsupported_code_page`;
- `malformed_dbf` / `malformed_memo`;
- `ambiguous_target` / `target_not_found`;
- `precondition_failed` / `lossy_encoding`;
- `validation_failed` / `commit_failed` / `recovery_required`.

Tool responses include a safe message, structured category, relevant location,
and suggested corrective action. Internal stack traces are not exposed.

## 12. Testing ownership

| Component | Primary tests |
|---|---|
| DBF/FPT codec | golden bytes, malformed boundaries, endianness, property tests |
| Encoding | per-code-page round trips and rejection tests |
| Properties/Methods | formatting preservation and scoped edit contracts |
| Tree | paths, duplicate names, missing parents, cycles, casing |
| Query/Output | snapshots, pagination, response limits |
| Edit planners | semantic result plus exact byte-footprint assertions |
| PairCommit | fault injection at every durable-write boundary |
| Writer | locking, stale identity, backup, recovery, journal state |
| MCP adapter | schema contracts, annotations, error translation |
| Whole system | disposable corpus plus VFP 6/9 acceptance matrix |

## 13. Deferred components

The following are explicitly deferred until justified:

- HTTP transport and multi-user authentication;
- production DBF/DBC data access;
- a full VFP language parser;
- form execution or compilation;
- menu, report, and label editing;
- structural editing and packing;
- multiple concurrent writer processes.
- following external class paths or opening referenced data tables.
