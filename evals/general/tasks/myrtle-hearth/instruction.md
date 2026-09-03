# Myrtle Hearth — the Birch sound-change engine

The **Birch school** of historical linguistics reconstructs a proto-language
by applying an *ordered* sequence of sound changes to each word. Your job:
build `derive.py`, the school's ordered sound-change derivation engine, and
run it on the visible proto-forms to ship the derived lexicon.

A **word** is a sequence of **segment tokens** (non-whitespace strings), one
line per word in a lexicon file, segments separated by spaces, e.g.
`p a t e r`. `#` is the reserved **word-edge** marker and `0` the reserved
**deletion/insertion marker**; neither can ever be a real segment.

## Fixtures already in `/app` (read-only)

- `/app/rules.json` — the visible change list (see format below).
- `/app/lexicon.txt` — the visible proto-forms (8 words; blank lines and
  lines starting with `#` are ignored).

## Rule file format

`rules.json` is a JSON object with a `changes` list, applied **strictly in
list order**: the output of rule *k* is the input of rule *k*+1. Each change:

```json
{"target": "p", "result": "f", "left": "#", "right": "a", "note": "..."}
```

- `target` — a segment (substitution/deletion rule) or `"0"` (insertion
  rule). Must not be `"#"`.
- `result` — a segment (substitute/insert), or `"0"` (delete). Must not be
  `"#"`. `result: "0"` with `target: "0"` is malformed.
- `left`, `right` — optional context; missing or `""` means **no constraint
  (any context)**; `"#"` means the word edge; any other string is a literal
  segment that must be present. For **insertion rules** (`target: "0"`),
  `left`/`right` must each be `"#"` or a literal segment — an empty/missing
  context makes that insertion rule never match.
- `note` — free text, ignored by the engine.

## Matching semantics (exact — implement precisely this)

For each rule, on the word as it stands **when the rule begins**:

1. Compute **all** matching positions on that **pre-pass form** (the word is
   not modified while matches are being collected).
2. Apply one change at **every** match. This is a **single left-to-right
   pass per rule**: each matched segment is rewritten exactly once, and the
   rule never re-scans its own output (no intra-rule iteration). Because a
   change at one position shifts the positions to its right, an
   implementation applies the precomputed matches from highest position to
   lowest — the observable result is: every segment that matched on the
   pre-pass form gets its change, and insertions land between their two
   context segments.

Substitution/deletion rule (`target` is a segment `T`) on word
`s0 s1 ... s(n-1)`:

- position `i` matches iff `s[i] == T` and
  - `left == "#"` requires `i == 0`; `left == ""` always ok; otherwise
    `i >= 1` and `s[i-1] == left`;
  - `right == "#"` requires `i == n-1`; `right == ""` always ok; otherwise
    `i+1 <= n-1` and `s[i+1] == right`.
- `result == "0"`: the matched segment is deleted; otherwise it is replaced
  by `result`.

Insertion rule (`target == "0"`) — an `n`-segment word has boundaries
`b = 0..n` (`0` = before `s0`, `n` = after `s(n-1)`):

- boundary `b` matches iff
  - `left == "#"` requires `b == 0`; otherwise `b >= 1` and `s[b-1] == left`;
  - `right == "#"` requires `b == n`; otherwise `b <= n-1` and `s[b] == right`.
- `result` is inserted at **every** matching boundary.

A word may shrink to **zero segments** (everything deleted); the fully
deleted derived form is written as an empty field (nothing after the tab).

## CLI contract (deliverable 1: `/app/derive.py`)

```
python3 /app/derive.py <rules.json> <lexicon.txt> <out.tsv>
```

- Reads the two inputs, derives every word, writes `out.tsv`: **one line per
  non-ignored lexicon word, in file order**, `input<TAB>derived`, each line
  ending with `\n` (last line included; an empty result writes zero lines /
  zero bytes). The `input` column is the **trimmed line exactly as written**
  (interior whitespace preserved); the `derived` column is the derived
  segments joined with single spaces, or empty for a fully deleted word.
- Lexicon parsing: read lines, trim surrounding whitespace; skip blank lines
  and lines whose first character is `#` (comments). Words are the remaining
  whitespace-separated tokens.
- Exit codes: `0` success; `2` if the argument count is not exactly 3
  (print `usage: python3 derive.py <rules.json> <lexicon.txt> <out.tsv>` to
  stderr); `1` for any other failure with a brief message to stderr — an
  unreadable/unparseable `rules.json`, a malformed change (missing
  `target`/`result`, non-string values, `target`/`result` equal to `"#"`,
  `result "0"` on an insertion rule), an unreadable `lexicon.txt`, a lexicon
  word containing a reserved token (`#` or `0`), or an unwritable `out.tsv`.

## Deliverables

1. `/app/derive.py` — the engine, pure stdlib Python, no network.
2. `/app/derived.tsv` — run your engine on the visible pair:
   ```
   python3 /app/derive.py /app/rules.json /app/lexicon.txt /app/derived.tsv
   ```

## How the grader probes it

- Executes `python3 /app/derive.py` on the visible pair and on **hidden
  (rules.json, lexicon.txt) pairs** you have not seen, then compares each
  output byte-for-byte against the grader's own independent recomputation of
  the documented semantics. Hidden pairs exercise: feeding and bleeding
  chains where rule order changes the result, insertion rules (initial,
  final, medial), edge-conditioned (`#`) changes, words where **nothing**
  applies, a fully deleted word, adjacent matches on one pre-pass form, and
  interior spacing preserved in the `input` column.
- Requires `/app/derived.tsv` to equal the grader's recomputation of the
  visible pair.
- Checks the exit-code contract: wrong argument count → `2`; missing/unparseable
  inputs → `1`; empty lexicon → `0` with an empty output file.

Constraints: pure stdlib Python (`json`, `sys`), no third-party packages, no
network of any kind.