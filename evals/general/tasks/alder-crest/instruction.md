# Alder Crest — errata bulletin rewrite desk

You run the production desk of a small journal. Each errata bulletin is a
LaTeX-style frame (`frame.tex`) that inlines a subordinate body chapter
(`body_chapter.tex`). House style says the body may only use **permitted
synonyms** listed in `allowed.map`; you must rewrite the body chapter by
swapping words to their permitted synonyms while leaving the frame and the
synonym map themselves **byte-identical**.

Build a reusable program, `/app/solve.py`, that performs this rewrite on **any**
paper directory following the layout below — the shipped one and fresh ones the
verifier mounts — and writes a JSON report. It is not a one-off for the shipped
paths.

## Environment

- Working directory: `/app`. The shipped paper lives at `/app/press/`.
- Python 3.12 (`python3`) is available. Standard library only.
- **Do not modify `/app/press/frame.tex` or `/app/press/allowed.map`.** They are
  inputs; the verifier hashes both and fails you if either changes by a single
  byte. Do not modify anything else under `/app/press/` either except as
  described below.

## Paper layout (`<press_dir>`)

```
<press_dir>/
  frame.tex          LaTeX-style frame (PROTECTED)
  allowed.map        permitted-synonym map (PROTECTED)
  body_chapter.tex   subordinate include to rewrite (the editable part)
```

### allowed.map
Plain text, one `key=synonym` mapping per line. Blank lines and lines starting
with `#` are comments and are ignored. Only words whose **core** (see below)
equals a key — compared case-insensitively — are permitted to be rewritten;
every other word must be left exactly alone.

### Body rewrite rules
Process `body_chapter.tex` as whitespace-separated **tokens**. For each token:

1. Let `core` be the token with all leading and trailing punctuation removed,
   where punctuation is the characters `.,;:!?'\"()` (leading and trailing
   only, repeatedly). Let `lead`/`trail` be the removed punctuation.
2. If `core` is empty or no key in the map matches `core`
   case-insensitively, keep the token **verbatim** (punctuation included).
3. Otherwise replace the token with `lead + word + trail`, where `word` is the
   map's synonym, case-adjusted to match the core:
   - if the core is all-uppercase (length > 1) → the synonym in UPPERCASE;
   - else if the core starts with an uppercase letter → the synonym Capitalized;
   - else → the synonym in lowercase.

Examples (given `folio=leaf`): `(Folio)` → `(Leaf)`; `FOLIO;` → `LEAF;`;
`folio,` → `leaf,`; `folio-dash` → `folio-dash` (the dashed whole is not a key).

The edited body is the tokens joined by **single spaces** (original line
structure of the body is not preserved — the body is retokenized).

### Rendering the compiled page
Read `frame.tex` and replace **every occurrence of the marker substring**
`%%INCLUDE-BODY%%` with the edited body text (with any trailing newline of the
edited body stripped). Everything else in the frame is untouched. The result is
the **compiled page**.

## CLI contract for /app/solve.py

```
python3 /app/solve.py <press_dir> <compiled_out> <report_out>
```

- `<press_dir>` — a paper directory as laid out above.
- `<compiled_out>` — where the compiled page is written (UTF-8 text).
- `<report_out>` — where the JSON report is written.

All paths come from `sys.argv`; no hard-coded paths. Use only the standard
library. The verifier runs the program unchanged on hidden paper directories.

## The JSON report (written to `<report_out>`)

Exactly these keys:

```json
{
  "edited_sha256": "<hex>",
  "compiled_sha256": "<hex>",
  "frame_sha256": "<hex>",
  "map_sha256": "<hex>",
  "replacements": 10
}
```

- `edited_sha256` — sha256 hex of the edited body text (the exact string
  inlined into the compiled page; trailing newline stripped), UTF-8 encoded.
- `compiled_sha256` — sha256 hex of the compiled page file contents.
- `frame_sha256` — sha256 hex of the **original, untouched** `frame.tex`.
- `map_sha256` — sha256 hex of the **original, untouched** `allowed.map`.
- `replacements` — how many body tokens were actually substituted (int).
- All digests are lowercase hex.

## Deliverables

1. `/app/solve.py` — the reusable program.
2. `/app/compiled.tex` — the compiled page produced by running
   `python3 /app/solve.py /app/press /app/compiled.tex /app/answer.json`
   on the shipped paper.
3. `/app/answer.json` — the JSON report from that same run.

## Edge cases the verifier's hidden papers probe

- Marker `%%INCLUDE-BODY%%` appearing **inline** (mid-line) in the frame, and
  frames with extra header/footer lines around it.
- ALL-CAPS and Capitalized permitted tokens (synonym case must follow the
  core, per the rules above); punctuation on both ends of a token.
- Hyphenated compounds such as `glyph-margin` (never rewritten, since the whole
  core is not a key), tokens that are pure punctuation, and words absent from
  the map (left verbatim).
- Synonym maps with comments, blank lines, and keys that never occur in the
  body; repeated permitted words.
- An **empty body chapter** — the compiled page is the frame with the marker
  removed and `replacements` is 0.
- Protected-file immutability: `frame.tex` and `allowed.map` must be
  byte-identical before and after your program runs.

No network access; standard library only.
