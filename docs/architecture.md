# VFP MCP Architecture

**Status:** Draft for review  
**Project:** `vfp_mcp`  
**Last updated:** August 25, 2026

## 1. Purpose

`vfp_mcp` will expose Visual FoxPro 6 and Visual FoxPro 9 form (`.SCX`/`.SCT`)
and class-library (`.VCX`/`.VCT`) source through the Model Context Protocol
(MCP). Its first
responsibility is safe, precise comprehension: discovery, hierarchy,
properties, bindings, layout, and method source. Guarded edits to existing
properties and method blocks follow only after the codec has passed acceptance
testing in both Visual FoxPro 6 and Visual FoxPro 9.

The server does not execute or compile VFP code, modify compiled executables,
or automate the VFP IDE. Structural designer operations such as adding and
reparenting controls are a later phase.

## 2. Architectural principles

1. **Preserve source fidelity.** Unknown fields, binary memos, formatting, and
   record order remain byte-identical unless an operation explicitly changes
   them.
2. **Separate semantics from storage.** MCP-facing operations use forms,
   controls, properties, and methods; only the codec handles DBF/FPT details.
3. **Pure planning, controlled effects.** Parsing and edit planning are pure.
   A single stateful writer owns locking, backup, disk I/O, validation, and
   recovery.
4. **Read broadly, write narrowly.** Read operations may describe whole
   projects. Initial writes target one existing property or method block and
   require explicit preconditions.
5. **Reject ambiguity.** Mutation targets use full hierarchy paths, expected
   values or match counts, and lossless text encoding.
6. **Every mutation is reviewable and reversible.** A write produces a paired
   backup, journal record, post-write validation result, and semantic diff.
7. **VFP is the authority.** Parsing our own output is necessary but does not
   replace opening, compiling, and running representative edits in VFP 6 and 9.

## 3. Scope by release phase

### Phase 0: codec and acceptance spike

- Parse representative and edge-case SCX/SCT and VCX/VCT pairs.
- Model properties, methods, object paths, and containment.
- Reproduce a targeted memo edit on disposable copies.
- Establish VFP 6/9 acceptance, timestamp behavior, OBJCODE invalidation, and
  record-order implications.

### Phase 1: read-only MCP server

- Project discovery and summaries.
- Control trees and details.
- Method inventories and retrieval.
- Property, code, class, and data-binding search.
- Validation and bounded textual layout rendering.

### Phase 2: guarded property and code edits

- Typed property updates and geometry operations on one SCX target per transaction.
- Event-scoped method replacement and exactly-one-match literal patches.
- Paired backups, edit journal, validation, diff, and restore.
- Mandatory prepare/apply plan IDs, current pair hashes, and dry-run previews.

### Phase 3: structural editing

- Add, soft-delete, rename, and reparent controls.
- Tab-order and, if proven safe, Z-order operations.
- Explicit memo/deleted-record packing.

## 4. System context

```text
MCP client / AI agent
        |
        | MCP over stdio (initially)
        v
VFP MCP server
        |
        +-- reads and validates source pairs
        +-- returns semantic trees, code, bindings, layouts, and diffs
        +-- performs serialized, guarded edits when enabled
        |
        v
Configured VFP project root
  forms/*.scx + *.sct
  class libraries/*.vcx + *.vct
```

The project root is an explicit trust boundary. All accepted paths are
canonicalized and must remain beneath it. A deployed server may serve an
original LecoWin2 or SBT project when a user deliberately configures that root;
development and automated tests use isolated copies. The server does not open
production data tables merely because a form references them.

Each process declares one target compatibility version with `--vfp-version 6`
or `--vfp-version 9`. Mixed-version files may be inspected with warnings, but
writes are blocked when the target file cannot be shown compatible with the
declared version.

## 5. Runtime architecture

```text
MCP transport
  -> Server / tool dispatcher
       -> Discovery and path policy
       -> Semantic query services
            -> parsed-document cache
            -> pure codec and model
       -> Mutation service
            -> single serialized writer
            -> backup and journal
            -> pure edit planner
            -> ordered pair writer
            -> post-write parser and validator
```

The MCP adapter contains protocol concerns only: schemas, annotations,
pagination, output limits, and conversion of domain errors into tool results.
The codec and application services remain usable from tests and a CLI without
starting MCP.

## 6. Source model

### Physical representation

- SCX and VCX files use a DBF-family record container.
- SCT and VCT files use FoxPro FPT memo storage.
- Memo fields contain four-byte little-endian block pointers.
- FPT header and memo-block integers are big-endian.
- Block size is read from the FPT header; zero means 512 bytes.
- Deleted records use the standard `0x2A` marker.

### Semantic representation

A parsed document contains:

- pair identity and file metadata;
- DBF schema and code-page information;
- active and deleted records with stable physical indices;
- typed object metadata (`CLASS`, `BASECLASS`, `OBJNAME`, `PARENT`);
- raw and parsed property/method text;
- untouched raw bytes for unknown and opaque content;
- a containment graph and path index;
- validation findings.

Controls are addressed by a canonical full path. `OBJNAME` alone is not a
safe mutation identity because the same name can appear in different parents.

## 7. Read path

1. Resolve and authorize the requested source pair beneath the configured root.
2. Stat both files and look for a cache entry with the same identity.
3. Read immutable byte snapshots of both files.
4. Parse headers, schema, records, pointers, and memo blocks with bounds checks.
5. Decode textual fields according to the file code page.
6. Build the semantic document, hierarchy, and path index.
7. Run structural validation.
8. Shape and bound the requested MCP response.

The cache is an optimization, not a source of truth. Mutations always parse a
fresh disk snapshot.

## 8. Write transaction

An edit is planned against a fresh parsed document and executed as follows:

1. Verify write mode, pair existence, path confinement, and exclusive access.
2. Verify the target path and operation-specific preconditions.
3. Create a consistent backup of both files and record its hashes.
4. Produce a pure edit plan containing memo appends and exact DBF byte patches.
5. Reject unrepresentable text or changes outside the declared edit footprint.
6. Materialize and durably write the new memo file first.
7. Materialize and durably write the DBF file containing the new pointers.
8. Reopen and parse the resulting pair from disk.
9. Validate the pair and verify the requested semantic postcondition.
10. Commit the journal entry, invalidate the cache, and return a structured diff.

Prepare and apply are separate operations. The prepare response contains a
short-lived plan ID, pair hash, semantic diff, physical footprint, and expiry.
Apply accepts only that exact plan while the pair hash and explicit write mode
remain valid.

Memo data is appended rather than overwritten in place. If interruption occurs
before the DBF pointer changes, the safe failure is an orphan memo block. The
exact Windows replacement and recovery protocol remains a design decision and
must be proven with fault-injection tests.

Method edits invalidate the corresponding `OBJCODE`. Timestamp updates will
not be enabled until their VFP 6/9-compatible encoding is established.

## 9. Concurrency and consistency

- One server process serializes all mutations.
- Reads may run concurrently against immutable byte snapshots.
- A write takes an exclusive-open/lock on both members of the pair.
- A write checks that file identity has not changed between planning and commit.
- Cache entries are keyed by canonical pair path and a content identity stronger
  than modification time alone where practical.
- One mutation call is the unit of audit, backup, validation, and rollback.

Multiple independent server instances are not assumed safe unless a later
cross-process locking design explicitly supports them.

## 10. Security boundaries

- Confine all paths beneath a configured project root.
- Default to read-only operation unless `--write` is explicitly enabled.
- Never interpret or execute VFP source.
- Do not traverse form bindings into DBF/DBC production data by default.
- Cap, paginate, or summarize large outputs.
- Emit operational logs on `stderr` only; MCP `stdout` is reserved for protocol
  messages.
- Preserve OLE and unknown binary memos without decoding or rewriting them.
- Avoid logging full source arguments where they may contain secrets; journal
  redaction and retention policy remain configurable decisions.

## 11. Validation strategy

Validation is layered:

- **Container:** header lengths, record counts, field boundaries, deletion flags.
- **Memo:** pointer range, block header, length bounds, block type, overlap.
- **Encoding:** known code page and lossless decode/encode for modified text.
- **Model:** parent resolution, cycle detection, sibling-name ambiguity, bookends.
- **Edit footprint:** only declared records, pointers, timestamps, and appended
  memo regions changed.
- **Semantic postcondition:** the requested property or method value is observable
  after reparsing.
- **VFP acceptance:** representative artifacts open, compile, and run in their
  originating VFP 6 or VFP 9 environment.

## 12. Deployment

The proposed implementation is an Elixir OTP application with an `ex_mcp`
adapter behind a project-owned protocol boundary and a custom codec. Initial
transport is stdio only. Each process requires `--root` and `--vfp-version 6|9`;
`--write` is optional and absent by default. Development uses Mix; distribution
is a self-contained Windows executable.

The precise MCP SDK and packaging mechanism are pending confirmation because
their versions and operational trade-offs can change independently of the
codec.

## 13. Quality gates

Write capabilities cannot advance beyond experimental status until:

- the supported corpus parses without unexplained critical findings;
- byte-level edit-footprint tests pass;
- recovery behavior is tested at each interruption point;
- modified fixtures pass independent parse and semantic verification;
- representative edits are accepted by VFP 6 and VFP 9;
- backup restoration is demonstrated;
- opaque and unsupported fields remain unchanged.

## 14. Open architectural decisions

The remaining decisions are implementation gates rather than product choices:

1. Exact VFP 6/VFP 9 timestamp encoding and rewrite behavior.
2. Windows pair-replacement and crash-recovery behavior under fault injection.
3. Acceptance of representative edits in both VFP versions.
4. Whether opaque OLE memo preservation can be demonstrated synthetically.

Settled choices include one root per process, VFP 6 and 9 with a declared
compatibility gate, stdio-only transport,
read-only-by-default operation, advisory Git integration, local `.vfp_mcp/`
backups with the latest 20 per form, metadata-plus-diff journals,
slash-separated percent-escaped paths, strict Windows-1252 writes, read-only
VCX inspection, SCX-only guarded writes, no production-data access, and deferred
structural editing.
