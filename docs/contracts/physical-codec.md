# Physical DBF/FPT Codec

<!--
specled covers:
- vfp_mcp.codec.dbf_structure
- vfp_mcp.codec.memo_pointer
- vfp_mcp.codec.fpt_structure
- vfp_mcp.codec.memo_block
- vfp_mcp.codec.lossless_encoding
- vfp_mcp.codec.raw_fidelity
- vfp_mcp.codec.pure_planning
- vfp_mcp.read.immutable_snapshot
- vfp_mcp.read.validation_findings
- vfp_mcp.read.source_fidelity
-->

`VfpMcp.Codec.parse_pair/2` is a deterministic transformation of an immutable
`PairSnapshot`. It performs no filesystem access and produces either a
`VfpMcp.Document` containing the complete physical model or fatal findings with
no partial document.

## DBF representation

`VfpMcp.Codec.Dbf` retains the fixed header, descriptor region, terminator,
optional header extension, records, and trailing bytes. Header values and every
descriptor, record, deletion marker, and field value include absolute byte
spans. Unsupported field types remain opaque fixed-width values. Deleted
records remain in physical order.

Schema validation completes before record fields are sliced. Invalid header or
record extents, missing or truncated descriptors, zero field widths, and
cumulative width mismatches are fatal. Duplicate names and invalid record
markers block mutation while retaining bounded physical content. Unusual
trailing bytes and unknown field types are warnings whose bytes remain
unchanged.

## FPT representation

`VfpMcp.Codec.Fpt` retains the 512-byte header, any pre-data alignment bytes,
the declared allocation region, resolved blocks, unresolved bytes, and trailing
content. Both the stored and effective block size are recorded; stored zero is
normalized to an effective 512 bytes.

Memo pointers are read from four-byte DBF field slices as little-endian block
numbers. FPT header and block integers are big-endian. Every `MemoRef` retains
its DBF record, field, raw pointer, and pointer span. Empty, resolved, and failed
resolutions are explicit. Shared pointers keep distinct references to one block
identity. Out-of-range, truncated, excessive, or overlapping blocks expose no
payload as valid through their references.

## Text boundary

DBF code-page driver IDs `0x03` and `0x57` resolve to Windows-1252. Character
fields and type-1 memo payloads get separate UTF-8 views while their original
bytes remain authoritative. Unsupported code pages and undefined Windows-1252
bytes retain raw content and add mutation-blocking findings.

`VfpMcp.Codec.Encoding.encode/2` is strict. It returns bytes only when every
Unicode code point has an exact Windows-1252 representation; it never emits
replacement characters or partial output.

## Fidelity summary

`VfpMcp.Codec.PhysicalSummary` produces canonical JSON containing only scalar
metadata, offsets, lengths, states, and SHA-256 values. Field names, fixed-width
values, and memo payload bodies are represented by hashes rather than embedded
source content. Equal snapshots therefore produce byte-identical summaries and
stable finding order without leaking full source.
