# Item-064 (hard) — Regex-only classifier, adversarial corpus, legal-move generator

This is the **hard** escalation of the regex-rule-engine task. The mechanism is
identical to the medium contract (see below), but the corpus is *adversarial*:
lookalikes are designed to defeat naive regexes, canonicalization must be
faithful, and the chess generator must be correct for **both sides to move**,
including castling, en passant promotion and the legality filter.  Getting the
**last-match ordering** exactly right is part of the score.

## Files in /app

- `engine.py` — **fixed**; provides `substitute(text, rules)` and
  `classify(text, rules)`. **Do not modify.**
- `run.py` — **fixed** driver: reads `records.txt` + `rules.json`, classifies,
  attaches `legal_moves` to valid-FEN records, writes `output.json`.
  **Do not modify.**
- `records.txt` — the **adversarial corpus**.
- `rules.json` — author this: `substitution` (rewrites, `re.sub` in order) and
  `classification` (tag rules, `re.fullmatch`, **last match wins**).
- `moves.py` — repair so `legal_moves(fen)` returns the *sorted* UCI legal
  moves for any legal FEN (either side to move).  The shipped copy omits
  castling, en passant, promotion and the legality filter.
- `python-chess` is installed for your own cross-checking only — it must NOT be
  imported by `/app/moves.py`.

## The record classes (exact contract)

`ipv4`
- valid ⇔ exactly four decimal octets joined by `.`, each octet `0..255`, no
  leading zeros.  So `192.168.0.1`, `10.0.0.1`, `255.255.255.255` are valid;
  `256.0.0.1`, `999.999.999.999`, `12.34.56.789`, `01.2.3.4`, `2024.0.0.1` are
  invalid.
- A **port suffix** `:NNNNN` (5 digits) after a 4-octet literal is a legitimate
  IPv4 literal: it is *valid* and **canonicalizes** by stripping the port
  (e.g. `127.0.0.1:8080` → canonical `127.0.0.1`).
- Five groups (`1.2.3.4.5`) is not an IPv4: `none`.

`date`
- valid ⇔ canonical form `YYYY-MM-DD` is a real proleptic Gregorian date
  (month lengths + leap years: `02-29` only in leap years — `2000-02-29` valid,
  `1900-02-29` invalid).
- canonicalization is required for variants: `MM/DD/YYYY` and `DD.MM.YYYY`
  become `YYYY-MM-DD` (e.g. `31.12.2020` → `2020-12-31`).
- non-padded forms like `2023-2-3` exist: they are classified **date/invalid**
  (they do not become canonical), and `YYYY-MM-DD` with a bad day/month
  (`2024-04-31`, `2024-13-01`) is invalid.
- `2023-02-29`, `2024-13-01`, `2023-2-3` → invalid.

`fen`
- `fen/valid` ⇔ the full 6-field shape `placement turn castling ep halfmove
  fullmove` with `turn` ∈ {w,b}, castling `-` or `[KQkq]{1,4}`, ep `-` or
  `[a-h][36]`, halfmove integer, fullmove integer ≥ 1.
- anything else that looks like 8 ranks joined by `/` (with or without
  malformed trailing fields) → `fen/invalid`.
- `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR` (no metadata) → invalid;
  `... w KQkq - 0` (missing fullmove) → invalid; `4k3/... w - - 0 0`
  (fullmove 0) → invalid.

`none` — everything else (`hello world trust`, `aaaa:bbbb:ddee`).

## Last-match traps to reason about deliberately

1. A broad `ipv4`/invalid catch and a strict `ipv4`/valid rule: the strict one
   must come **after** the catch so valid literals upgrade, while lookalikes
   keep the catch's `invalid`.
2. `date` invalid-catch then strict valid-date: same ordering requirement.
3. `fen` lookalike then strict full FEN: the strict one must be last so a valid
   FEN upgrades to `valid`.

Turning prose into a test matrix before coding is the intended workflow:
build the expected (kind, verdict, canonical) row for every line of
`records.txt`, then author rules, then iterate until the matrix is respected.

## Move generator requirements (hard additional coverage)

`legal_moves` must be correct for **both** `w` and `b` to move.  The corpus
contains FENs that force: en passant capture (`8/8/8/3Pp3/8/8/8/K6k w - e6
0 1`), promotion with the four lower-case UCI suffixes
(`7k/4P3/8/8/8/8/8/4K3 w - - 0 1`), white and **black** castling
(`r3k2r/...R3K2R w KQkq - 0 1` and `r3k2r/8/8/8/8/8/8/R3K2R b q - 0 1`), a
black-to-move start position, and filter-out-moves-that-expose-your-king for
both colors.

## Steps

1. Read `engine.py`, `run.py`, `records.txt`.
2. Build your test matrix, author `rules.json` (mind ordering), author/replace
   `moves.py` with a correct generator.
3. `cd /app && python3 run.py` → `output.json`.
4. Cross-check with `python3 -c "import chess; print(sorted(...))"` (do not
   import chess in `/app/moves.py`).
5. Iterate until your matrix is satisfied.

## Deliverable

Same as the medium task: `/app/output.json`, one object per `records.txt` line:
`{text, canonical, kind, verdict}` plus `moves` (sorted UCI) for valid-FEN
records.  The verifier re-runs the fixed engine against an independent
reference ruleset and compares every record; full match → reward 1.