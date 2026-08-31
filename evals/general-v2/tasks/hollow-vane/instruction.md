# hollow-vane — reassemble the scattered payload recipe

The **hollow-vane** activation service expects a single integer payload before
it will sign a deployment. The recipe for that payload was scattered across a
directory of plain-text "clue" artifacts by the upstream team. You must work
out the payload for the provided clue set **and** ship a reusable derivation
program, because the grader will run your program on clue sets you have never
seen.

The container has Python 3.12 (`python3`) and `jq`; there is **no network
access**. Work in `/app`. The provided clue set lives at `/app/clues/`
(described below).

## Deliverables (both required)

1. `/app/payload.py` — a runnable Python program with this interface:
   ```
   python3 /app/payload.py <clue_root> [outfile]
   ```
   - It derives the payload from the clue directory `<clue_root>` and prints
     it to **stdout** as a decimal integer (e.g. `27931` or `-12`), with a
     trailing newline.
   - If the optional second argument `outfile` is given (and is not `-`), it
     must also write the payload followed by a single newline to that path,
     creating parent directories as needed. With no second argument it writes
     to `/app/answer.txt`.
   - It must work on **any** clue directory conforming to the format below —
     the verifier runs it unchanged on hidden clue sets.

2. `/app/answer.txt` — the payload your program derives for the provided
   `/app/clues/` (exactly the integer and a trailing newline):
   ```
   python3 /app/payload.py /app/clues
   ```

## Clue-directory format

A clue root contains any subset of:

- **`seed.env`** — `KEY=VALUE` lines. Ignore blank lines and lines starting
  with `#`. Tolerate surrounding whitespace around keys and values. The seed
  is the integer value of the `SEED` key. If `seed.env` is missing, has no
  `SEED` key, or the value is not parseable as an integer, the seed is `0`.
  All other keys are ignored.

- **`cutoff.txt`** — a single ISO date `YYYY-MM-DD` (tolerate surrounding
  whitespace/blank lines). It is the **inclusive lower bound**: only journal
  entries dated on or after the cutoff are applied. If `cutoff.txt` is missing
  or unparseable, there is no cutoff (every valid entry applies).

- **`journal/`** — a directory of entry files. Only files whose name matches
  `entry-<N>.txt` where `<N>` is a run of digits (e.g. `entry-0007.txt`,
  `entry-42.txt`) are entries; anything else in the directory (any contents)
  is ignored. Each entry file holds three `key: value` lines, in any order,
  possibly with blank lines and extra whitespace around keys and values:
  - `date:` an ISO date `YYYY-MM-DD`
  - `op:` one of exactly `add`, `sub`, `mul`, `xor`
  - `value:` an integer (may be negative)
  An entry is **skipped entirely** (applies nothing) if: it is dated before
  the cutoff; its date, op, or value is missing/unparseable/invalid; its op is
  not one of the four; or reading it raises any error.

## Derivation rule

Start with the seed. Consider only the valid, in-cutoff entries, ordered by
the **numeric** value of `<N>` in the filename (so `entry-9` sorts before
`entry-10`, regardless of zero padding). Apply each in turn to the running
value `v`:

- `add O` → `v + O`
- `sub O` → `v - O`
- `mul O` → `v * O`
- `xor O` → `v ^ O` (Python integer XOR semantics)

The final running value is the payload. Print it as a decimal integer via
Python `str(int)` (so `-12`, `0`, `27931`).

Example: with seed `10` and valid entries `entry-1: add 5`,
`entry-2: mul 3`, the payload is `(10 + 5) * 3 = 45`.

## Edge cases the grader probes (hidden clue sets)

- Cutoff filtering: entries dated before the cutoff are skipped; entries on
  the cutoff date itself apply.
- Malformed entries (missing fields, unknown ops, non-integer values) are
  skipped without disturbing the rest.
- Non-entry filenames (e.g. `README.txt`, `entry-BAD.txt`, `.gitkeep`) are
  ignored entirely.
- Missing `seed.env` / missing `cutoff.txt` / missing `journal/` (empty
  journal directory or absent directory) — the program must not crash.
- Numeric filename ordering (`entry-10` after `entry-9`), unpadded numbers,
  large integers, and negative values/operands.

## Rules

- Do **not** modify anything under `/app/clues/` (the grader verifies the
  bytes of the whole tree).
- Do not read or modify `/tests` or `/solution`.
- No network access; Python standard library only.
- Everything must be deterministic.