# Research: A VFP Form (.SCX) Management MCP Server in Elixir

<!--
specled covers:
- vfp_mcp.codec.dbf_structure
- vfp_mcp.codec.memo_pointer
- vfp_mcp.codec.fpt_structure
- vfp_mcp.codec.memo_block
- vfp_mcp.codec.parse_mixed_endian_pair
-->

**Status:** Research / design document
**Date:** August 2026
**Context:** LecoWin2 production-management system (VFP 9, ~95 forms, `visual classes\dynamic.vcx` class library). All byte-level format claims below were **verified experimentally** against this repository's files during August 2026 sessions (see `scripts\dump-scx.ps1` and `scripts\edit-scx-memo.ps1`, the working PowerShell proofs-of-concept this document productizes).

---

## Table of Contents

1. [Executive summary](#1-executive-summary)
2. [Goals and non-goals](#2-goals-and-non-goals)
3. [The .SCX/.SCT format — complete working reference](#3-the-scx-sct-format--complete-working-reference)
4. [What "understanding a form" means for an LLM](#4-what-understanding-a-form-means-for-an-llm)
5. [MCP primer — what we are building on](#5-mcp-primer--what-we-are-building-on)
6. [Why Elixir — and why not something else](#6-why-elixir--and-why-not-something-else)
7. [SDK selection for Elixir](#7-sdk-selection-for-elixir)
8. [Server architecture](#8-server-architecture)
9. [The tool catalog — every tool and why it exists](#9-the-tool-catalog--every-tool-and-why-it-exists)
10. [The write path — engineering details](#10-the-write-path--engineering-details)
11. [Safety, security and concurrency model](#11-safety-security-and-concurrency-model)
12. [Resources and prompts (secondary MCP surfaces)](#12-resources-and-prompts-secondary-mcp-surfaces)
13. [Testing strategy](#13-testing-strategy)
14. [Risks, unknowns and open questions](#14-risks-unknowns-and-open-questions)
15. [Phased roadmap](#15-phased-roadmap)
16. [Appendix A — byte-level format tables](#16-appendix-a--byte-level-format-tables)
17. [Appendix B — example tool schema](#17-appendix-b--example-tool-schema)

---

## 1. Executive summary

We propose **`vfp_form_mcp`**: an Elixir MCP server that gives an LLM complete,
safe read and write access to Visual FoxPro form files (`.scx`/`.sct`) — the
control hierarchy including deeply nested controls (pages, grids, columns,
containers), every control property, and every line of event code stored in the
METHODS memo fields.

The feasibility is already proven: during exploration of this repository we
built PowerShell scripts that (a) fully parse SCX/SCT pairs into a human-readable
dump including the containment tree, and (b) perform surgical edits — moving a
textbox by rewriting its `Left`/`Top` properties, and rewriting event code —
by appending a memo block and repointing a 4-byte pointer. The server is the
industrialization of those scripts: robust format handling, an LLM-ergonomic
tool surface, backups, validation, and diffing.

**Recommended stack:** Elixir + [`ex_mcp`](https://hex.pm/packages/ex_mcp)
(1.0.0-rc line, MIT, stdio transport) + a custom DBF/FPT codec (existing Hex
DBF libraries are read-only and do not understand VFP memo-write semantics) +
OTP supervision with a single-writer GenServer for mutations.

**Guiding design principle:** *reading is cheap and safe, writing is
transactional and always reversible.* Every mutation tool auto-backs up,
returns a structured diff, and can be undone; every read tool is shaped for
how an LLM actually consumes context (trees, paths, sketches — not raw table
dumps).

---

## 2. Goals and non-goals

### Goals

- **G1 — Comprehension:** an LLM can answer "what does this form look like and
  how does it behave?" including nested containers, data bindings, and event code.
- **G2 — Property mutation:** change any control property (position, size,
  captions, ControlSource, colors, enabled/visible, etc.).
- **G3 — Code mutation:** read, replace, patch, and append event/method code
  (`PROCEDURE Click ... ENDPROC` blocks in METHODS memos).
- **G4 — Structure mutation (later phase):** add, delete (soft), rename, and
  reparent controls, including containers with children.
- **G5 — Project-level awareness:** search across all 95 forms for a code
  snippet, a ControlSource, a caption — impact analysis before refactoring.
- **G6 — Safety:** no edit can silently corrupt a form; every edit is backed
  up, validated post-write, diffed, and reversible. Files open in VFP are never
  touched.
- **G7 — VCX parity:** the same tooling works against class libraries
  (`dynamic.vcx`), because forms derive from `dynform`, `dyntextbox`, etc. —
  an LLM cannot reason about a form's inherited behavior without reading the VCX.

### Non-goals (explicitly out of scope, at least initially)

- Running or compiling VFP code; launching the VFP IDE.
- Editing `.mnx` menus, reports (`.frx`), or labels (`.lbx`). The same codec
  generalizes to them (all are DBF+FPT pairs) — the format layer supports it,
  but the tool surface stays forms-focused until needed.
- Multi-writer collaboration. One server instance, one write path, one user at
  a time — matching how VFP developers actually work with form designers.
- Migrating VFP syntax to another language (a client-side concern; the server
  just provides faithful reads/edits).

---

## 3. The .SCX/.SCT format — complete working reference

Everything in this section is verified against this repo unless flagged.
This is the foundation the codec module implements.

### 3.1 High-level structure

| File | Role |
|---|---|
| `forms\login.scx` | A dBASE-family **DBF table** holding one row per form object (form, dataenvironment, each control) |
| `forms\login.SCT` | The **FPT memo file** holding all long text: properties sheets, method code, compiled objcode, OLE blobs |

The "form" is therefore a relational table, not a source file. This is what
makes programmatic management both possible and delicate.

### 3.2 DBF container specifics (verified)

- Header: record count at offset 4 (int32 LE), header length at 8 (uint16 LE),
  record length at 10 (uint16 LE); field descriptors are 32 bytes each starting
  at offset 32, terminated by `0x0D`.
- Codepage driver ID sits in header byte 29; this project's files are
  **Windows-1252** (French accented text, e.g. `Saisie de mot-de-passe`).
- Deleted records carry flag byte `0x2A` (`*`) as first byte; live records
  `0x20`. Soft delete is the DBF-native "recycle bin" — we exploit it for
  `delete_control`.
- Character fields are space-padded, N fields are ASCII text (not binary!) —
  e.g. TIMESTAMP is stored as 10 ASCII chars.

### 3.3 SCX schema (verified field list)

```
PLATFORM    C 8      "WINDOWS" for objects; "COMMENT" for bookend/aux rows
UNIQUEID    C 10     designer-generated id (used for grid column linkage etc.)
TIMESTAMP   N 10     VFP-internal timestamp
CLASS       M        class name when instance of a custom class (e.g. dynform)
CLASSLOC    M        .vcx path for custom classes
BASECLASS   M        VFP base class: form, textbox, commandbutton, pageframe,
                     page, grid, column, header, container, optiongroup, label,
                     image, dataenvironment, cursor, relation, ...
OBJNAME     M        object name (the identity LLMs will address)
PARENT      M        name of container object ("frmLogin", "page2", ...) —
                     empty for the form/dataenvironment roots
PROPERTIES  M        the property sheet, one `Name = Value` per line
PROTECTED   M        list of protected members (class libs)
METHODS     M        event/method code: `PROCEDURE <name> ... ENDPROC` blocks
OBJCODE     M        compiled code cache
OLE, OLE2   M        OLE/ActiveX payloads
RESERVED1-8 M        designer metadata (preserve verbatim; mostly ignorable)
USER        M        free-use
```

### 3.4 Record semantics (verified on login.scx: 11 records)

- Row 0 and the last row are **bookends** (`PLATFORM = "COMMENT"`); the last
  bookend carries the font character-set sheet (`Arial, 0, 9, 5, 15, 12, 32, 3, 0`).
- One `dataenvironment` record, then its `cursor`/`relation` children.
- One `form` record (`BASECLASS=form`, `CLASS=dynform` here).
- Then one record per control, in creation order, with `PARENT` naming the
  containing object. **Nesting is fully expressed by the PARENT chain** — e.g.
  a grid column header is `PARENT = column3`, whose `PARENT = grid1`, whose
  `PARENT = page2`, whose `PARENT = pageframe1`, whose `PARENT = frmProd`.
- Container base classes in VFP: `formset, form, pageframe, page, grid,
  column, container, optiongroup, commandgroup, toolbar`. Coordinates in
  PROPERTIES (`Top/Left/Width/Height`) are **pixels relative to the parent
  container**, not the form.

### 3.5 PROPERTIES memo grammar (verified)

```
Height = 120
Width = 332
Caption = "Saisie de mot-de-passe"
ControlSource = "thisform.cUserID"
PasswordChar = "*"
cuserid =            <- user-defined form properties appear here too
```

- One property per line, `Name = <VFP literal>`.
- Literals follow VFP syntax: strings in double quotes (internal quotes
  doubled), logicals `.T.`/`.F.`, numerics plain, dates `{^yyyy-mm-dd}`,
  expressions start with `=` in some contexts.
- Empty value = property with no default.
- **Editing rule (critical):** rewrite only the targeted lines, keep every
  other line byte-identical. Line-scoped editing is what makes surgical
  property changes safe.

### 3.6 METHODS memo grammar (verified)

```
PROCEDURE Click
  select users
  LOCATE FOR cUserid = padr(trim(thisform.cUserId),15)
  ...
ENDPROC
```

- One block per event/method. Code is VFP (line continuation `;`, string
  concatenation `+`, comments `*`/`&&`), Windows-1252 encoded.
- Parsing into `{event_name, code}` pairs is reliable on
  `^PROCEDURE\s+(\w+)` ... `^ENDPROC` boundaries.

### 3.7 FPT memo file specifics (verified — the part everyone gets wrong)

1. **Memo pointers in the DBF are 4-byte binary little-endian block numbers** —
   *not* the 10-character ASCII digit strings of classic dBASE. Reading them
   as text yields garbage (we hit this exact bug).
2. **Block size lives in the FPT header bytes 6–7 (big-endian).** VFP commonly
   writes **1** (making a pointer a raw byte offset — this project's files) or
   **64**; field value 0 must be treated as 512 (dBASE default). Never assume 512.
3. **Block layout:** `[4-byte BE type][4-byte BE length][data]`. In this
   project's SCT files VFP writes **type = 1** for form memo blocks (verified
   empirically). A writer should clone the type of the block it replaces.
4. **Header bytes 0–3 (big-endian) = next free block.** Any append must update it.
5. FPT header is 512 bytes regardless of block size.

### 3.8 The safe edit algorithm (implemented and demonstrated in PowerShell)

Never modify memo data in place. Instead:

1. Serialize the new memo text (Windows-1252).
2. Append at end of FPT, aligned to the block size:
   `[type=original type][BE length][data]`.
3. Update FPT header next-free pointer.
4. Rewrite the record's 4-byte LE pointer in the DBF.
5. For METHODS changes, **zero the OBJCODE pointer** — stale compiled code is
   otherwise used until VFP notices (VFP would detect the timestamp mismatch
   itself, but forcing recompile is deterministic).
6. The old block becomes orphaned free space; VFP's `PACK MEMO` reclaims it.
   Orphan accumulation is bounded and harmless.

Demonstrated on this repo: `Left = 210 → 240` / `Top = 12 → 25` move of
`txtcUserID`, and METHODS text replacement, each leaving all other records
byte-identical (verified by binary diff: only 4 pointer bytes changed in the
DBF).

### 3.9 Constraints

- The SCX/SCT pair **must not be open in VFP** while we write.
- `lecowin.exe` embeds compiled forms: source edits require a project rebuild
  to reach production, but edited forms open immediately in the VFP designer.
- Z-order among siblings is believed to be record order (VFP's "bring to
  front/back" reorders records) — **flagged unverified**, see §14.

---

## 4. What "understanding a form" means for an LLM

An LLM cannot reason from a raw 11-record table dump the way it reasons from
source code. The tool surface must translate the relational representation
into LLM-native shapes. Four shapes matter:

1. **The path-addressed tree.** Controls need unambiguous addresses:
   `frmProd/pageframe1/page2/grid1.column3.text1`. This mirrors how VFP
   programmers speak ("the textbox in column 3 of the grid on page 2") and
   gives every subsequent edit tool a precise, collision-free target — unlike
   OBJNAME alone, which is only unique within a parent in the general case.
2. **The spatial sketch.** `Top/Left/Width/Height` numbers are hard to reason
   about; a text-mode rendering of the form (boxes with captions, optionally
   annotated with tab order) lets the model "see" the screen. This is the
   single highest-leverage comprehension tool — spatial mistakes (overlapping
   controls, cramped layouts) become visible.
3. **The code inventory.** "Which controls have code, and which events?" is
   the map; per-control code retrieval is the territory.
4. **The binding map.** ControlSource / RecordSource / dataenvironment
   cursors and relations connect UI to the data dictionary — essential in this
   project where forms bind to `production.dbc` tables.

Everything in the tool catalog below exists to serve one of these four shapes,
or to mutate them safely.

---

## 5. MCP primer — what we are building on

[Model Context Protocol](https://modelcontextprotocol.io) is a JSON-RPC 2.0
protocol for connecting tools/data to LLM clients (Claude Code/Desktop, opencode,
Cursor, ...). As of the 2025-06-18 specification (current at time of writing):

- **Tools** are model-invoked functions with a `name`, human-readable
  `description`, a JSON-Schema `inputSchema`, optional `outputSchema`, and
  optional `annotations` (`readOnlyHint`, `destructiveHint`, `idempotentHint`,
  `openWorldHint`) that clients use for trust decisions. Results carry
  `content` blocks (text/image/resource-link) and may carry
  `structuredContent` JSON validated against `outputSchema`. Errors inside
  tool execution are reported via `isError: true` results, not JSON-RPC errors.
- **Transports:** stdio (spawned by the client; simplest and right for us) and
  Streamable HTTP (remote/team deployments, later).
- **Resources** (`resources/list`, `resources/read`) are server-addressed data
  URIs — good for "the full dump of form X" attachments.
- **Prompts** are canned prompt templates.
- The spec **recommends a human in the loop** for destructive operations —
  clients surface confirmation UI; our annotations must be honest so that
  machinery works.

Design consequences for us:

- Tools must be **few enough to fit a model's attention** but complete; we
  group by workflow and use structured outputs for machine-parseable results.
- Every tool `description` doubles as documentation — written for an LLM that
  has never heard of dBASE.
- Read tools: `readOnlyHint: true`. Mutating tools: honest `destructiveHint`
  and human-review-friendly diffs.

---

## 6. Why Elixir — and why not something else

Honest framing first: MCP servers exist in TypeScript and Python ecosystems
that are larger. This project is nonetheless a strong Elixir fit:

1. **Binary pattern matching.** The codec is fixed-offset binary parsing and
   byte-surgery. Elixir's `<<count::little-integer-32, hdr_len::little-integer-16, _::binary>>`
   style makes the DBF/FPT layer declarative, reviewable, and testable against
   golden bytes — no endianness foot-guns (we hit both LE pointers and BE
   lengths in the same format; binaries make the distinction explicit).
2. **Fault isolation.** Each tool call can run under a supervised task. A
   crash on one malformed SCX returns a clean tool error, never a dead server.
   Given we are mutating binary files an LLM asked us to touch, "crash-only
   hurts the request" is exactly the failure model we want.
3. **Single-writer discipline maps to OTP.** All mutations flow through one
   GenServer (§8), giving serialized, transactional writes with zero locks,
   plus an ETS read cache invalidated by write-through — the standard OTP
   shape.
4. **Deployment fit.** Target users are Windows/VFP shops. An Elixir server
   ships as a self-contained escript (or [Burrito](https://github.com/burrito-elixir/burrito)
   wrapped exe) — no Node/Python runtime to install next to a VFP machine.
5. **The write algorithm is append-mostly and stateless per call** — no need
   for persistent connections, ORM, or web framework; the BEAM is optional
   muscle here, but it is free muscle.

Accepted trade-offs: smaller MCP talent pool, and the SDKs are younger than
the official TS/Python ones (mitigated in §7).

---

## 7. SDK selection for Elixir

There is **no official Anthropic Elixir SDK** in the modelcontextprotocol org
(verified Aug 2026). The Hex ecosystem has matured considerably; leading
candidates evaluated:

| Package | Version line | Transports | Notes |
|---|---|---|---|
| **`ex_mcp`** (azmaveth) | 0.12.0 stable / **1.0.0-rc.8** (Jun 2026) | stdio, HTTP/SSE, in-BEAM | Full server+client, tools/resources/prompts, MIT, active (24 releases), ACP extras irrelevant here |
| `hermes_mcp` | 0.14.1 | stdio, HTTP, Phoenix-centric | Solid; heavier Phoenix coupling than we need |
| `fastest_mcp` | 0.3.1 | stdio, Streamable HTTP | FastMCP-style DSL; young |
| `noizu_mcp` | 0.1.5 | stdio, Streamable HTTP | Full spec surface incl. sampling/elicitation |
| `conduit_mcp` | 0.10.1 | Streamable HTTP+SSE, auth, CORS | Web-first; stdio not the focus |
| `mcp_elixir_sdk` | 1.1.0 | stdio, Streamable HTTP | "Official-style"; smaller community |

**Choice: `ex_mcp`**, pinned to 1.0.0-rc (or 0.12.0 if RC is unpalatable),
stdio transport, single-session server. Rationale: most active release
cadence, clean separation of transport from protocol, stdio is first-class,
MIT, and its tool-definition API is macro-free enough to generate our ~25-tool
catalog from data (tool specs defined as Elixir maps → JSON Schema) rather
than handwriting schemas. Fallback: `hermes_mcp` if we later want the server
embedded in a Phoenix app for team use — the codec layer is SDK-agnostic by
design (pure functions; see §8).

DBF parsing on Hex was also surveyed: `elixir_dbf` (dBASE III-level),
`dbf_ex` (read-only), `ex_dbase` (dBASE III). None handle **VFP binary memo
pointers** or **FPT append-write semantics** — both of which are core to this
project. **Decision: custom codec** (`VfpMcp.Dbf` / `VfpMcp.Fpt`), ~300 lines
of binaries, fully owned and tested against golden files from this repo.

---

## 8. Server architecture

```
                       ┌─────────────────────────────────────────────┐
 MCP client (stdio) ──▶│ VfpMcp.Server (ex_mcp session process)      │
                       │   tool dispatch, arg validation, output     │
                       │   shaping (trees, sketches, diffs)          │
                       └───────┬─────────────────────┬───────────────┘
                               │ read                │ write
                    ┌──────────▼─────────┐  ┌────────▼──────────────┐
                    │ VfpMcp.Cache (ETS) │  │ VfpMcp.Writer         │
                    │ {path ⇒ parsed     │  │ (single GenServer)    │
                    │  form, mtime/size} │  │ backup → edit → fsync │
                    └──────────┬─────────┘  │ → validate → cache    │
                               │            └────────┬──────────────┘
                     ┌─────────▼──────────────────────▼─────────┐
                     │ VfpMcp.Codec (pure, no state)            │
                     │  Dbf    — DBF header/fields/records      │
                     │  Fpt    — memo read + append-write       │
                     │  Scx    — record ⇄ domain struct         │
                     │  Props  — PROPERTIES parse/render        │
                     │  Code   — METHODS parse/render           │
                     │  Tree   — hierarchy build/validate       │
                     │  Layout — ASCII renderer                 │
                     │  Cp1252 — encoding boundary              │
                     └───────────────────────────────────────────┘
```

Key decisions:

- **Codec is pure.** `parse(path) :: form_doc`, `apply_edit(form_doc, edit) ::
  {new_dbf, new_fpt_append, side_effects}`. Pure functions = trivial property
  testing and golden-file diffs; the GenServers only manage state and I/O.
- **Cache invalidation by `(mtime, size)`** on every read; write-through after
  mutation. Parsing a 200-record form is sub-millisecond; the cache exists to
  keep multi-tool workflows consistent, not for speed.
- **Single-writer GenServer.** All mutating tools call
  `VfpMcp.Writer.run(form_path, edits)`. One call at a time, one process:
  atomic per-call semantics, natural audit log (every edit appended to a
  JSONL journal with before/after), trivially correct backup ordering.
- **Windows-1252 at the boundary.** Internal representation is UTF-8
  binaries; encode/decode exclusively inside `Cp1252`. MCP is JSON/UTF-8 —
  never leak 1252 bytes.
- **Config** (env/config.exs): `root_dir` (all paths resolved and confined
  under it), `read_only` mode flag, `backup_dir` (default
  `<root>/.vfp_mcp_backups`), `max_text_output` guard.

---

## 9. The tool catalog — every tool and why it exists

Naming: `snake_case` verbs. Paths use dot/slash notation
(`form/pageframe1/page2/grid1.column3.header1`). Every tool returns both a
human-readable `text` summary and, where useful, `structuredContent`.

### 9.1 Discovery & comprehension (read-only)

| # | Tool | Input (essence) | Returns | Why it exists |
|---|-----|-----------------|---------|---------------|
| 1 | `list_forms` | `—` (or filter) | all SCX/VCX under root: name, caption, class, record count, control count, mtime | **Entry point.** The model's first call on any task; orients it in the 95-form surface without touching files' contents. |
| 2 | `get_form_overview` | `form` | form-level props (caption, size, window type), class + parent-class chain, dataenvironment summary (aliases/tables), counts by base class | Cheap context. Lets the model decide *whether* to descend. Prevents the classic failure of dumping a 200-control form into context when it only needed the shape. |
| 3 | `get_control_tree` | `form`, optional `root` path | path-addressed nested tree: type, name, key props (caption, position, bindings), children | **The understanding tool.** PARENT-chain resolution is exactly what an LLM can't do reliably from raw records. Nesting depth (pageframe→page→grid→column→header/control) is flattened into addresses here once, correctly. |
| 4 | `get_control_details` | `form`, `path` | everything: full property map, class chain (CLASS + resolved VCX ancestry), event list with signatures, PROTECTED members, record metadata (uniqueid, timestamp) | Precision on demand. `get_control_tree` summarizes; this is the complete record for one object — the "open the property sheet" action. |
| 5 | `render_form_layout` | `form`, optional `container` path, `annotate: tab/none` | ASCII-art sketch: boxes, captions, relative positions; optional [n] tab-order markers | LLMs reason spatially from sketches far better than from coordinate lists (§4). Catches overlap/cramping before the user does. Rendering is scoped to any container (a page, a grid) not just the form. |
| 6 | `get_dataenvironment` | `form` | cursors (alias, source table/database, filters, order, readonly), relations (parent/child alias, keys) | The binding map: what data the form touches. In this project that means `production.dbc` tables — indispensable for impact analysis ("does any form bind SHIPDET?"). |
| 7 | `list_classes` | `—` | classes in VCX(es): name, baseclass, parent class, member counts | Forms here are built from `dyn*` classes; without the VCX the model sees unexplained inherited behavior. |
| 8 | `get_class_details` | `class` | like #4 for a VCX class | Same rationale; VCX records are structurally identical to SCX (same schema) — one codec serves both. |

### 9.2 Reading code (read-only)

| # | Tool | Input | Returns | Why |
|---|-----|-------|---------|-----|
| 9 | `list_code_locations` | `form` | every object with non-empty METHODS: path + event names (+ line counts) | The code inventory/map (§4.3). Cheap way to answer "what behavior exists on this form". |
| 10 | `get_control_code` | `form`, `path`, optional `event` | verbatim code, one event or all | The territory. Verbatim = no paraphrase risk. |
| 11 | `get_form_code` | `form` | all code concatenated with `PATH (event)` headers | Whole-form logic in one call for refactoring/review workflows; the format an LLM reviews best. |
| 12 | `search_forms` | `query` (regex or literal), `scope: code/properties/all`, optional form list, context lines | matches: form, path, event/property, excerpt | **Project-level impact analysis** (G5). "Which of 95 forms references `users.cPassword`?" — currently impossible without opening every form in VFP. |

### 9.3 Property mutation (write)

| # | Tool | Input | Returns | Why |
|---|-----|-------|---------|-----|
| 13 | `set_control_properties` | `form`, `path`, `props: [{name, value}]` | applied diff (before/after per property) | The workhorse (G2). Takes **typed values in JSON** (number/bool/string) and renders correct VFP literals — the model never hand-writes `"Caption = \"…\""` text patches, eliminating quote/formatting corruption. Batch per call = one backup, one write, one diff. Unknown property names are allowed (custom props like `cuserid`) but flagged. |
| 14 | `move_control` | `form`, `path`, `dx/dy` or `to: {x,y}` | new geometry | Semantics instead of text surgery. A naive model doing find/replace on `Left = 210` hits *the wrong control's* `210` — path-targeted edits remove that class of accident entirely. |
| 15 | `resize_control` | `form`, `path`, `to: {w,h}` or deltas | new geometry | Same rationale; auto-adjacent use with #14 for layout fixes found via #5. |
| 16 | `normalize_layout` | `form`, `container`, rules | aligned coordinates | Optional convenience (align edges, equal spacing). Models asked to "tidy this form" otherwise emit dozens of individual moves. |

### 9.4 Code mutation (write)

| # | Tool | Input | Returns | Why |
|---|-----|-------|---------|-----|
| 17 | `set_control_method` | `form`, `path`, `event`, `code` | diff | Replaces **one event block** (`PROCEDURE Click … ENDPROC`), creating it if absent. Event-scoped replacement is the natural unit of VFP code change; whole-METHODS replacement invites the model to silently drop sibling handlers. |
| 18 | `patch_control_code` | `form`, `path`, `find`, `replace`, optional `event` scope, `expected_count` | diff + match count | Surgical find/replace (the proven `edit-scx-memo.ps1` semantic). `expected_count` guards against replacing in more places than the model believes exist — a cheap, highly effective misedit tripwire. |
| 19 | `delete_control_method` | `form`, `path`, `event` | diff | Removing behavior cleanly (empty stubs left by "clear the code" edits are a real VFP annoyance). |

All three auto-zero OBJCODE (§3.8 step 5) and refresh the record timestamp.

### 9.5 Structural mutation (write, later phase — highest risk)

| # | Tool | Input | Returns | Why |
|---|-----|-------|---------|-----|
| 20 | `add_control` | `form`, `parent`, `baseclass`, `name`, initial props, optional `template: path to clone from` | new path | G4. **Clone-first strategy:** new SCX records carry designer conventions (RESERVED fields, CLASS/CLASSLOC pairing, UNIQUEID format) that are safest inherited from a real, VFP-authored record — either an existing control the model picks as template or our built-in per-baseclass templates harvested from this repo. Insert before the closing bookend row, wire PARENT, enforce name uniqueness under the parent. |
| 21 | `delete_control` | `form`, `path`, `mode: soft/default` | removed paths | Soft delete = set `0x2A` flag on the record **and all descendants** (PARENT cascade). Reversible until a later `pack` tool or VFP `PACK`. Physical delete is opt-in because it rewrites the whole DBF. |
| 22 | `rename_control` | `form`, `path`, `new_name`, `update_references: bool` | diff incl. reference rewrites | OBJNAME + PARENT refs must change in lockstep; `update_references` additionally (and optionally) rewrites `thisform.<old>` / `this.parent.<old>` occurrences in METHODS across the form — offered as explicit opt-in because it edits code strings. |
| 23 | `reparent_control` | `form`, `path`, `new_parent`, `at: {x,y}` or auto-translate | new path | Moves an object between containers **with coordinate translation** (Top/Left are parent-relative, §3.4 — the classic silent corruption if forgotten). |
| 24 | `set_tab_order` | `form`, `container`, ordered name list | diff | TabIndex properties rewritten per given order; z-order note: record-order manipulation is implemented but gated behind verification (§14). |
| 25 | `pack_form` | `form`, `what: memo/deleted` | stats | Reclaims orphaned memo blocks (re-file) and/or purges soft-deleted records. Explicit, destructive-annotated, requires the VFP-closed precondition. |

### 9.6 Safety & integrity (mixed)

| # | Tool | Input | Returns | Why |
|---|-----|-------|---------|-----|
| 26 | `validate_form` | `form` | findings: dangling PARENTs, cycles, out-of-range memo pointers, duplicate names under a parent, TabIndex gaps, encoding anomalies, bookend integrity | The pre-flight/post-edit loop (G6). Also the model's self-check after any mutation batch — and ours in tests. |
| 27 | `diff_form` | `form`, `against: backup/git/other` | structured diff: records added/removed (soft-deleted), memo-level text diffs | Review surface for humans and model alike: "show me exactly what the agent changed." Git integration = diff against `git show HEAD:<path>` when the repo is clean of VFP locks. |
| 28 | `backup_form` / `restore_form` | `form` / `form`, `backup_id` | backup id+location / restored | Auto-backup already runs on every write; these give the model (and user) explicit undo points. Backups are timestamped sibling copies in `backup_dir`, plus a JSONL edit journal per form. |

**Tool count: 28.** Grouped so that a client UI (and a model's planning)
sees: *read (1–12), write (13–25), safety (26–28)*. Descriptions carry
`readOnlyHint` for 1–12 and honest `destructiveHint` for 20–21 and 25.

---

## 10. The write path — engineering details

One mutation, end to end (inside `VfpMcp.Writer`):

1. **Preconditions:** file exists; exclusive open succeeds (fails cleanly if
   VFP or anything else holds it); not `.git`-ignored unintentionally
   (warn-only); read_only mode off.
2. **Backup:** copy SCX+SCT to `backup_dir/<form>.<yyyymmdd-hhmmss>.{scx,sct}`;
   journal entry `{ts, tool, args}` appended.
3. **Parse fresh** (never edit from cache), locate target record(s) by path.
4. **Compute edits** via pure codec: new memo text(s); for each changed memo,
   an append-plan `{new_block_offset, type, data}`; DBF byte patches
   (pointers, optional OBJCODE zero, TIMESTAMP refresh).
5. **Apply atomically:** write both files via `temp file → fsync → rename`
   per file; FPT first (a pointer to a not-yet-existing block must never be
   observable — rename order guarantees crash-safety in the practical sense;
   worst crash case leaves an orphan block and the old pointer, which is valid).
6. **Re-validate:** reparse from disk, run `validate_form` rules, verify the
   intended semantic change (e.g. property really has the new value).
7. **Respond** with structured diff + new mtime; refresh cache.

Encoding round-trip: UTF-8 ⇄ CP1252 with explicit replacement policy —
**lossless for 1252-representable text, reject otherwise** (never silently
`?`-replace French accents).

---

## 11. Safety, security and concurrency model

- **Path confinement.** All `form`/path arguments resolve under `root_dir`;
   traversal attempts are tool errors.
- **Honest annotations.** `readOnlyHint` on readers; `destructiveHint: true`
   on deletes/pack; clients then apply their human-in-the-loop UI per MCP's
   trust model. We deliberately do *not* mark property/code writes
   destructive (they are diffed and reversible) — over-flagging trains users
   to click through confirmations.
- **Single writer.** All mutations serialized by the Writer GenServer.
   Concurrent MCP sessions (e.g. two agents) get queued writes and an
   mtime-based optimistic check (a session's stale parse ⇒ explicit
   "form changed since you read it" error, not a blind clobber).
- **VFP interlock.** Exclusive-open probe before any write; documented rule:
   close the form in the VFP designer first. VFP itself locks table headers
   when forms are open — the probe catches it.
- **No secrets exposure.** The server reads only SCX/VCX pairs; it does not
   open the production DBC, so table *data* never transits the LLM context
   (form *bindings* do — that's metadata). Given this session already
   surfaced that `users.DBF` stores plaintext passwords, that boundary matters.
- **Resource hygiene.** Read tools cap output size (`max_text_output`),
   paginate `search_forms`, and steer toward `get_form_overview` → drill-down
   patterns via their descriptions.

---

## 12. Resources and prompts (secondary MCP surfaces)

- **Resources:** `vfp://forms` (index), `vfp://forms/{name}` (full text dump —
  the `scripts/dump-scx.ps1` output format, proven readable), `vfp://classes/{name}`.
  Lets a user pin a form into context for the whole session.
- **Prompts:** `/vfp-review-form <name>` (security + data-binding review
  checklist), `/vfp-document-form <name>` (generate markdown docs — seed for
  the repo's missing docs), `/vfp-find-dead-code` (handlers referencing
  removed tables). Low cost, high workflow value; purely optional sugar over
  the tools.

---

## 13. Testing strategy

- **Golden files.** This repo *is* the fixture corpus: 95 real forms +
  `dynamic.vcx`, including edge cases (pageframes, grids with explicit
  columns, OLE controls in `commtest.scx`, near-empty `dialogok.scx`).
- **Round-trip:** `parse → re-serialize unchanged memos → byte-identical`.
  Guaranteed by the append-only design and asserted continuously.
- **Edit contracts:** for each mutation tool: apply to golden copy → reparse →
  assert semantic result + assert "all other records byte-identical except
  documented pointer/timestamp bytes" (the binary-diff technique used in this
  session becomes an ExUnit assertion helper).
- **Property-based (StreamData):** random prop/code edits on random forms;
  invariants: file reparseable, tree well-formed, edit visible, nothing else
  moved.
- **Corpus fuzz:** every SCX in repo must parse with zero findings from
  `validate_form` *before* we trust the validator on edited files.
- **Phase-0 human gate:** edited copies of `login.scx` opened in an actual
  VFP9 designer — properties dialog, code windows, run the form — before any
  write tool ships. (PowerShell edits passed our own re-parse; VFP acceptance
  is the remaining proof.)

---

## 14. Risks, unknowns and open questions

| # | Risk / unknown | Impact | Mitigation |
|---|----------------|--------|------------|
| R1 | **Z-order = record order?** (community belief, unverified here) | reorder tools could scramble layering | Verify in Phase 0 by front/back-ing two overlapping labels in VFP and diffing record order; keep `set_tab_order` TabIndex-only until proven |
| R2 | **New-record fidelity (`add_control`)** — RESERVED fields/UNIQUEID conventions | VFP designer could reject/hide added controls | Clone-first strategy (§9.5 #20); VFP acceptance tests before GA |
| R3 | **Grid semantics** — ColumnCount=-1 (dynamic columns) means only *customized* columns exist as records | Model may think columns are missing | `get_control_tree` annotates dynamic column counts; docs in tool description |
| R4 | **OLE/ActiveX blobs** (OLE2 memos) | Opaque binary; corruption risk if touched | Codec never rewrites OLE fields; structural moves of OLE controls carry verbatim bytes |
| R5 | **Codepage drift** — mixed encodings across 25-year-old files | Mojibake on write | Per-file codepage detection from DBF byte 29 + 1252 default; lossless-or-reject policy |
| R6 | **RESERVED1–8 semantics** largely undocumented | Unknown designer-state coupling | Preserved verbatim always; only studied if VFP misbehaves |
| R7 | **FPT block type=1 vs 0** — we verified VFP writes 1 in SCTs; dBASE heritage says 0 | Strict readers might reject type-0 blocks | Codec clones original block type on append (already fixed in `edit-scx-memo.ps1`); R2-phase VFP test double-checks |
| R8 | **Formsets / multiple form records** in one SCX | Tree builder assumptions | Corpus survey in Phase 1; builder handles formset as a root if found |
| R9 | **MCP SDK at RC** (`ex_mcp` 1.0.0-rc.8) | API churn | Pin version; codec is SDK-independent; migration surface is one module |
| R10 | **Concurrent git + server edits** | Divergent histories | Document workflow (commit-before-agent-session); `diff_form` surfaces surprises |

---

## 15. Phased roadmap

| Phase | Scope | Exit criteria |
|-------|-------|---------------|
| **0 — Spike** | Port PowerShell logic to Elixir codec; parse all 95 forms + VCX; `edit` in Elixir; **VFP9 designer acceptance** on edited `login.scx` copies; R1 z-order experiment | Codec proven against real VFP, not just our own reader |
| **1 — Read-only server** | Tools 1–12 + resources; `validate_form` read rules | An LLM can fully describe any form in the repo, incl. nested controls; zero write capability shipped |
| **2 — Writes: props & code** | Tools 13–15, 17–19, 26–28; backups/journal; diffs | Agent performs caption/position/code edits that VFP opens cleanly; every edit reversible |
| **3 — Structure** | Tools 16, 20–25; clone templates; pack | Add/rename/reparent survive VFP acceptance; R2/R3 closed |
| **4 — Productize** | Prompts, pagination polish, escript/Burrito packaging, docs, installer for a VFP shop | A Windows user runs one exe + adds one MCP config entry |

---

## 16. Appendix A — byte-level format tables

### DBF header (verified)

| Offset | Size | Meaning |
|-------:|-----:|----------|
| 0 | 1 | version byte |
| 4 | 4 | record count (LE) |
| 8 | 2 | header length incl. terminator (LE) |
| 10 | 2 | record length (LE) |
| 29 | 1 | codepage driver ID |
| 32… | 32×n | field descriptors, `0x0D` terminated |

Field descriptor: name C11 (NUL/space padded), type C1, length at +16.
Record: `[flag 0x20/0x2A][fields in order]`.

### FPT header (verified)

| Offset | Size | Meaning |
|-------:|-----:|----------|
| 0 | 4 | next free block (**BE**) |
| 6 | 2 | block size (**BE**); 0 ⇒ 512; VFP often writes 1 or 64 |
| 8+ | — | free-block chain / data |

### Memo pointer & block

- In DBF record: 4-byte **little-endian** block number (0 = empty memo).
- Block at `ptr × block_size`: `[4B BE type][4B BE length][data]`;
  VFP SCT blocks observed with type = 1.

---

## 17. Appendix B — example tool schema

`get_control_tree` as served via `tools/list` (abridged):

```json
{
  "name": "get_control_tree",
  "description": "Return the full containment hierarchy of a VFP form as a path-addressed tree. Paths look like 'frmProd/pageframe1/page2/grid1.column3.text1' and are accepted by all other tools. Containers (form, pageframe, page, grid, column, container, optiongroup, commandgroup) have children; coordinates are parent-relative pixels.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "form":        { "type": "string", "description": "Form name, e.g. 'login' or 'forms/login.scx'" },
      "root":        { "type": "string", "description": "Optional subtree path" },
      "include":     { "type": "array", "items": { "enum": ["caption", "geometry", "bindings", "events"] },
                       "description": "Which key properties to inline (default: caption, geometry)" }
    },
    "required": ["form"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "form":  { "type": "string" },
      "nodes": { "type": "array", "items": { "$ref": "#/$defs/node" } }
    },
    "$defs": {
      "node": {
        "type": "object",
        "properties": {
          "path":     { "type": "string" },
          "baseclass":{ "type": "string" },
          "class":    { "type": "string" },
          "caption":  { "type": "string" },
          "top":      { "type": "integer" },
          "left":     { "type": "integer" },
          "width":    { "type": "integer" },
          "height":   { "type": "integer" },
          "children": { "type": "array", "items": { "$ref": "#/$defs/node" } }
        },
        "required": ["path", "baseclass"]
      }
    }
  },
  "annotations": { "readOnlyHint": true }
}
```

*— end of document —*
