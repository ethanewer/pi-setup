# Item-064 (medium) — Regex-only rule engine + FEN legal-move generator

You are working on a **compliance classifier** for a data-cleansing pipeline.
The pipeline reads a log file (`records.txt`) one line at a time and must tag
each line with a category, a validity verdict, and (for chess positions) the
full list of legal moves.  The unusual part is that **the classification logic
is expressed entirely as data** — regular expressions placed in a rules file —
never as imperative code.  The engine that consumes them is fixed and off-limits.

## Files in /app

- `engine.py` — the **fixed** regex engine (functions `substitute` and
  `classify`). **Do not modify.**
- `run.py` — the **fixed** pipeline driver: reads `records.txt` + `rules.json`,
  classifies through the engine, attaches `legal_moves` for valid FENs, and
  writes `/app/output.json`. **Do not modify.**
- `records.txt` — the corpus of lines to classify (one record per line).
- `rules.json` — **this is what you author.** It has two arrays:
  - `substitution` — rewrite rules. Each entry has `pattern` and `replace`
    (and optional `flags`). `pattern`/`replace` are passed to Python `re.sub`.
    Rules run in array order; a later rule may rewrite text an earlier one
    already changed.
  - `classification` — tag rules. Each entry has `id`, `pattern`, and the two
    emitted fields `kind` and `verdict`.  Patterns are `re.fullmatch`ed against
    the (already-substituted) text.
- `moves.py` — the legal-move generator. It exposes `legal_moves(fen)` and
  must return the **sorted list of legal UCI moves** for a FEN string.  The
  shipped copy is incomplete/buggy: it omits castling, en-passant, promotion
  and any legality (check) filter.  Repair it.
- `python-chess` is installed **so you can cross-check your generator
  interactively**, but you must **NOT import it inside `/app/moves.py`** — the
  verifier confirms the shipped generator is self-contained.

## Last-match semantics (important)

Re the `classification` array, rules are scanned **in list order** and the
**last** rule whose `pattern` matches the full string **wins**.  So a broad
"lookalike/invalid" catch can appear early, and the precise "valid" rule that
overrides it goes near the end.  Ordering is part of the design — reason about
it deliberately.

## Category / verdict contract

| kind | valid | invalid |
| --- | --- | --- |
| `ipv4` | exactly 4 decimal octets separated by `.`, each `0`..`255`, **no leading zero** in any octet | out-of-range octet (`256`, `999`), a leading-zero octet (`01`), or a wrong group count |
| `date` | a real proleptic Gregorian date `YYYY-MM-DD`: month `01`-`12`, day valid for that month, and `02-29` only in leap years | `2023-02-29`, `2024-04-31`, month `13`, day `00`/`32`, etc. |
| `fen` | a full 6-field FEN: `placement turn castling ep halfmove fullmove` | a chess-position *lookalike* that is missing a required field, has a bad turn char, bad castling letters, or a bad ep square |
| `none` | — | anything that is none of the above |

**Date canonicalization:** `MM/DD/YYYY`, `DD.MM.YYYY`, and already-ISO
`YYYY-MM-DD` all normalize to ISO `YYYY-MM-DD` in the `canonical` field.
IPv4 and FEN records are **not** canonicalized (`canonical == text`).

Notes to encode precisely:
- IPv4 strictness is a real regex exercise. `0.0.0.0`, `255.255.255.255`,
  `192.168.0.1`, `10.0.0.1` are valid; `256.0.0.1`, `999.999.999.999`,
  `12.34.56.789`, `01.2.3.4` are not; `1.2.3.4.5` (five groups) is `none`.
- Gregorian leap-year handling is required: `2024-02-29` valid, `2023-02-29`
  invalid, `2024-04-30` valid, `2024-04-31` invalid, `2024-13-01` invalid.
  Express `02/29/2024` via canonicalization: it becomes `2024-02-29`.
- FEN fields: `placement` is 8 slash-separated ranks of digits/pieces; turn is
  `w` or `b`; castling is `-` or a non-empty `KQkq` combination (case matters);
  ep square is `-` or `[a-h][36]`; halfmove is an integer; fullmove is an
  integer >= 1.  A line with only the placement (no metadata) is a `fen`
  *lookalike* -> `invalid`; a line with the full shape -> `valid`.

## Legal-move generator requirements

`legal_moves(fen)` must return the correct, sorted list of UCI legal moves.  It
must handle without shortcuts:

- **castling** — `e1g1`/`e1c1` (white) and `e8g1`/`e8c1` (black), only when the
  king and rook are unmoved, the squares between are empty, the king is not in
  check, and it does not pass through an attacked square.
- **en passant** — a pawn on the 5th rank capturing an enemy pawn that has just
  double-pushed (the ep square is given in the FEN).
- **promotion** — a pawn reaching the last rank produces four UCI moves with a
  lowercase promotion suffix: `...e8q`, `...e8r`, `...e8b`, `...e8n`.
- **legality filter** — do **not** emit moves that leave your own king in check,
  and do not emit king captures onto attacked squares.

## Steps

1. **Read the contract**: inspect `engine.py`, `run.py`, `records.txt`.
2. **Author `rules.json`** so the engine emits exactly the classifications above
   for every line in `records.txt`.  Test as you go with the supplied engine.
3. **Repair `moves.py`** so `legal_moves` is correct and complete.
4. **Generate the answer**: `cd /app && python3 run.py` writes `output.json`.
5. **Validate & iterate**: cross-check against the spec, and use
   `python3 -c "import chess; print(sorted(mp for m in chess.Board('FEN').legal_moves))"`
   to inspect reference move-sets while developing (just do not import chess in
   the final `/app/moves.py`).

## Deliverable

`/app/output.json` is an array, one object per `records.txt` line in the same
order:

```json
{ "text": "...", "canonical": "...", "kind": "ipv4"|"date"|"fen"|"none",
  "verdict": "valid"|"invalid"|"none" }
```

and additionally, for records where `kind == "fen"` and `verdict == "valid"`:

```json
{ "...": "...", "moves": ["a2a3", "e2e4", "..."] }
```

`sorted` UCI strings. The verifier re-runs the identical engine against a
reference ruleset and compares record-by-record; your `output.json` must match.