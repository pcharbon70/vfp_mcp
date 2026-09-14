# Semantic VFP Source Codec

<!--
specled covers:
- vfp_mcp.codec.property_edit_scope
- vfp_mcp.codec.method_edit_scope
- vfp_mcp.codec.semantic_document
- vfp_mcp.codec.raw_fidelity
- vfp_mcp.codec.pure_planning
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
