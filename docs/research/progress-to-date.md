# VFP form direct-access research: progress to date

**Project:** `vfp_mcp`  
**Research source:** LecoWin2, a Visual FoxPro 9 production-management application  
**Research period:** August 20–21, 2026  
**Status:** format exploration and working PowerShell proofs of concept; the Elixir MCP server is designed but not yet implemented

## 1. Purpose

This work investigates whether an external tool can safely understand and modify Visual FoxPro form and class-library source files without driving the Visual FoxPro IDE. The eventual product is intended to be an MCP server through which an AI agent can inspect forms, search their code and properties, make narrowly scoped changes, validate the result, and show a reviewable diff.

The investigation concentrated on Visual FoxPro form pairs (`.SCX`/`.SCT`) and class-library pairs (`.VCX`/`.VCT`). It did not attempt to execute VFP code, replace the VFP compiler, or edit forms already embedded in a compiled executable.

## 2. Artifacts produced

The research produced three substantive artifacts:

1. `scripts/dump-scx.ps1` is a working reader for SCX/VCX DBF records and their SCT/VCT memo data. It emits readable object, property, and method information.
2. `scripts/edit-scx-memo.ps1` is a working targeted memo writer. It appends replacement memo data, repoints the corresponding SCX/VCX field, and can invalidate stale compiled object code.
3. `docs/research/architecture-and-format-research.md` is the detailed format reference and proposed architecture/tool catalog for an Elixir MCP server.

No Elixir application, `mix.exs`, MCP endpoint, or production codec has been implemented yet. References to modules such as `VfpMcp.Dbf`, `VfpMcp.Fpt`, `VfpMcp.Writer`, and `VfpMcp.Server` describe the proposed system rather than existing source code.

## 3. What an SCX form contains

An SCX file is a dBASE-family table. Each active record represents an object or a piece of designer metadata. The companion SCT file stores variable-length memo values referenced by fields in those records.

The examined SCX schema contains fields including:

- `PLATFORM`, `UNIQUEID`, `TIMESTAMP`, and reserved designer fields;
- `CLASS`, `CLASSLOC`, `BASECLASS`, `OBJNAME`, and `PARENT`, which describe object type and containment;
- `PROPERTIES`, containing serialized property assignments;
- `METHODS`, containing event and method source code;
- `OBJCODE`, containing compiled-code cache data;
- additional memo fields such as `OLE` and `OLE2`, which may hold opaque binary content.

The object hierarchy can be reconstructed from `OBJNAME` and `PARENT`. A form, page frame, page, grid, column, container, option group, command group, and their children can therefore be represented as stable paths such as:

```text
frmProduction/pageframe1/page2/grid1/column3/text1
```

Deleted DBF records use the ordinary `0x2A` deletion marker. Active records use `0x20`.

## 4. Memo representation established experimentally

The most important result was determining the actual pointer and byte-order rules used by the repository's VFP files.

### 4.1 Memo pointer

A memo field in an SCX/VCX record is a four-byte binary, little-endian block number. It is not an ASCII decimal field. A value of zero means the memo is empty.

### 4.2 Memo-file header

The SCT/VCT uses the FoxPro FPT layout. Bytes 0–3 of the memo header hold the next-free-block value in big-endian order. Bytes 6–7 hold the block size in big-endian order. A stored block size of zero represents 512 bytes.

The block size must always be read from the file. Files observed during the experiment used sizes including 1 and 64; assuming a universal 512-byte block size would read incorrect locations and make writes unsafe.

### 4.3 Memo block

At `block_number × block_size`, a memo block begins with:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | block type, big-endian |
| 4 | 4 | payload length, big-endian |
| 8 | variable | payload bytes |

The inspected VFP form memos used block type `1`. The writer preserves or clones the relevant type instead of relying on the older dBASE convention that text always uses type `0`.

### 4.4 Encoding

The proof-of-concept scripts decode and encode textual form data with Windows-1252. This matches the files used in the experiment, but a production codec needs to read the DBF code-page byte and reject a write when text cannot be represented losslessly.

## 5. Reading accomplished

The reader performs the following operations directly from bytes:

1. Reads record count, header length, and record length from the DBF header.
2. Walks the 32-byte field descriptors until the descriptor terminator.
3. Calculates each field's byte offset within a record.
4. Iterates records while respecting the deletion marker.
5. Reads fixed-width character fields such as object name, parent, class, and base class.
6. Interprets four-byte memo pointers.
7. Resolves blocks in the SCT/VCT using the file's declared block size.
8. Decodes property sheets and VFP method source into readable output.

The script accepts either SCX or VCX input and finds the corresponding SCT or VCT beside it. Output limits can be applied to method characters and property lines, but the defaults retain the full source.

This demonstrated that repository-wide form discovery, text extraction, code search, property inspection, and hierarchy construction do not require COM automation or a running VFP instance.

## 6. Property and method grammar observed

The `PROPERTIES` memo is line-oriented. It generally contains one assignment per line:

```foxpro
Caption = "Save"
Top = 120
Enabled = .T.
```

Values use VFP literal syntax rather than JSON or a generic configuration syntax. A future setter must render strings, logical values, numbers, dates, colors, arrays, and expressions conservatively and preserve formatting it does not understand.

The `METHODS` memo contains blocks such as:

```foxpro
PROCEDURE Click
  * VFP source code
ENDPROC
```

A form can contain several sibling procedure blocks in one memo. This led to the design decision that an MCP tool should normally replace or delete one named event block, or perform a guarded literal patch with an expected match count, rather than replace the entire memo.

## 7. Writing accomplished

The memo writer demonstrated a safe append-and-repoint strategy:

1. Load the SCX/VCX and SCT/VCT as byte arrays.
2. Locate exactly one object record by `OBJNAME`.
3. Locate the requested memo field, such as `METHODS` or `PROPERTIES`.
4. Read and decode the existing memo.
5. Apply either a literal find/replace operation or an explicit append.
6. Encode the result.
7. Calculate an aligned location after the current memo-file data.
8. Write a new block header and payload there.
9. Update the FPT next-free-block header.
10. Replace only the selected record field's four-byte pointer in the SCX/VCX.
11. Optionally zero the record's `OBJCODE` pointer.
12. Write the resulting files.

Existing memo blocks are never edited in place. The old block becomes unreachable and can later be reclaimed by VFP's `PACK MEMO`. This avoids overrunning a block when replacement text grows and minimizes changes to the DBF side of the pair.

In the controlled same-length replacement experiment, binary comparison confirmed that only the expected four memo-pointer bytes changed in the SCX. The new content was stored in an appended SCT block and could be read back through the parser.

## 8. Why OBJCODE must be handled

`METHODS` is source code, while `OBJCODE` is a compiled-code cache. Changing the source without invalidating compiled content can leave the record internally inconsistent.

The writer therefore offers `-ClearObjCode`, which sets the four-byte `OBJCODE` memo pointer to zero. VFP can then detect that compilation is required. The proposed production writer makes invalidation automatic for method mutations and also refreshes the appropriate record timestamp once that behavior has been validated with VFP.

Changing source files does not update an already built application. The VFP project and executable must still be rebuilt.

## 9. Safety model derived from the experiment

The following constraints are considered mandatory for a production writer:

- The SCX/SCT or VCX/VCT pair must not be open in VFP while it is written.
- Both members must be backed up together before a mutation.
- The memo block must be made durable before the DBF pointer references it.
- Every mutation should be parsed and validated immediately afterward.
- The system should verify an expected object, field, old value, and match count before writing.
- Writes should be serialized per form pair.
- OLE and unknown binary memo data must be preserved byte-for-byte unless a tool explicitly supports it.
- Encoding must be lossless; conversion failures should abort the edit.
- Backups and a journal should make recovery possible after interruption between the two file updates.
- Mutations should return a structured before/after diff.

The PowerShell spike proves the byte operations, but it does not yet provide all of these production protections.

## 10. Proposed MCP capabilities

The design document expands the proof of concept into several groups of MCP tools.

Read-only capabilities include project discovery, form summaries, object trees, control lookup, property inspection, method listing, individual method retrieval, and project-wide searches.

Lower-risk write capabilities include typed property updates, movement/resizing, guarded property patches, event-scoped method replacement, guarded code patches, and method deletion.

Higher-risk structural capabilities include adding controls, soft-deleting object subtrees, renaming, reparenting, tab-order changes, and packing. These should not ship until the unknown designer fields and record-order behavior have been validated in VFP itself.

Safety tools include form validation, structured diffing, backup listing/restoration, and explicit packing of orphaned memo blocks or deleted records.

## 11. Proposed implementation architecture

The proposed implementation is an Elixir application using a custom VFP codec and an MCP SDK such as `ex_mcp`:

```text
MCP transport
    -> VfpMcp.Server
        -> discovery/cache layer
        -> semantic form model
        -> serialized writer
            -> VfpMcp.Dbf
            -> VfpMcp.Fpt
```

The DBF/FPT codec should remain independent of MCP. Parsing and edit planning should be pure functions so that they can be tested with fixtures and property tests. The stateful writer owns locking, backups, journaling, ordered disk writes, validation, and rollback.

Existing Elixir DBF packages surveyed during the research were not sufficient because they were primarily dBASE III or read-only implementations and did not support the binary VFP memo-pointer and append-write semantics required here.

## 12. What remains unverified

Important risks and open questions remain:

1. **VFP acceptance:** edited copies must be opened, inspected, compiled, and run in VFP 9. Re-parsing our own output is necessary but not sufficient.
2. **Record order and Z-order:** it is plausible that sibling record order controls bring-to-front/send-to-back behavior, but this was not experimentally confirmed.
3. **New-record fidelity:** adding controls requires correct reserved fields, `UNIQUEID`, class metadata, bookend placement, and designer conventions.
4. **Timestamps:** the exact expected VFP timestamp update needs an acceptance test.
5. **Multiple code pages:** production behavior must not assume Windows-1252 for every historical form.
6. **OLE/ActiveX records:** opaque blobs must never be inadvertently decoded or rewritten.
7. **Crash recovery:** the pair of files cannot be atomically replaced by a single ordinary filesystem operation.
8. **Lock detection:** the server needs a dependable exclusive-open probe and useful error messages when VFP owns either file.
9. **Path identity:** duplicate object names can occur in different containers, so mutations must use full hierarchy paths rather than `OBJNAME` alone.
10. **All-form coverage:** the codec must parse every application form and relevant VCX library, not just the initial samples.

## 13. Recommended next milestone

The next milestone should remain a codec and VFP-acceptance spike, not a broad MCP tool implementation:

1. Create the Elixir application and dependency-free DBF/FPT codec modules.
2. Add sanitized SCX/SCT and VCX/VCT fixture pairs plus byte-level tests.
3. Parse every form and class library in LecoWin2 read-only.
4. Reproduce the existing memo edit against disposable copies.
5. Open those copies in VFP 9, inspect properties and code, compile them, and run them.
6. Perform a controlled Z-order experiment and compare record bytes.
7. Establish timestamp and `OBJCODE` behavior through VFP-authored before/after comparisons.
8. Only then expose read-only MCP tools, followed by narrowly scoped property and method writes.

## 14. Current conclusion

Direct SCX/SCT reading is demonstrated and useful now. Targeted memo writing is also demonstrated at the file-format level and is promising for property and method edits. The remaining gap is not basic byte access; it is production hardening and authoritative acceptance testing in VFP 9.

Structural form editing should be treated as a later, higher-risk phase. The most defensible first product is a read-oriented MCP server with search and form comprehension, followed by guarded edits to existing properties and individual method blocks with backup, validation, and diffing on every operation.
