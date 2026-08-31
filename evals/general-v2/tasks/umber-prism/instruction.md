# UmberPrism — descriptor screening: molar-mass proximity ranking

You are the computational chemist for **UmberPrism Materials**. A candidate
compound list has arrived as JSON Lines with **chemical formulas**, together
with an atomic-mass lookup table and a screening target. You must build a
reusable command-line screening program that parses each formula, computes the
**molar mass** descriptor from the lookup table, keeps only candidates whose
descriptor lies within a tolerance of a target value, ranks them by proximity,
and reports normalisation bookkeeping. The program must work **on any input**
conforming to the contract below, not just on the provided files.

## Environment

- Working directory: `/app`. It already contains `/app/compounds.jsonl`,
  `/app/atomic_masses.json` and `/app/screen.json`. Python 3.12 is available
  as `python3` (standard library only; no network access).
- **Do not modify `/app/compounds.jsonl`, `/app/atomic_masses.json` or
  `/app/screen.json`.**

## Deliverables (all three required)

1. `/app/screen.py` — a runnable Python program with this interface:
   ```
   python3 /app/screen.py --compounds FILE --masses FILE --screen FILE --output-jsonl OUT --report REPORT
   ```
2. `/app/ranked.jsonl` — the ranked list your program produces **when run on
   the provided visible inputs**:
   ```
   python3 /app/screen.py --compounds /app/compounds.jsonl --masses /app/atomic_masses.json --screen /app/screen.json --output-jsonl /app/ranked.jsonl --report /app/screen_report.json
   ```
3. `/app/screen_report.json` — the report produced by the same run.

## Input formats

**`compounds.jsonl`**: newline-delimited JSON objects. Every non-empty line
counts as one candidate row. Relevant field: `"formula"` (a string; rows
missing it, or carrying a non-string, are invalid). Rows may carry any other
fields — ignore them.

**`atomic_masses.json`**: a JSON object mapping element symbols to atomic
masses, e.g. `{"H": 1.008, "He": 4.003, ...}`. An element absent from this
table makes any formula containing it invalid.

**`screen.json`**: `{"target": <number>, "tolerance": <number>}`.

## Formula grammar (parse exactly this)

A formula string is one or more **parts** separated by the hydrate dot:

- `·` (U+00B7), or the ASCII period `.` — both are part separators.

Each part consists of an **optional leading integer multiplier** (default 1;
e.g. the part `5H2O` in `CuSO4·5H2O` means 5 × H2O) followed by a sequence of
**groups**. A group is:

- an **element**: an uppercase letter optionally followed by lowercase letters
  (e.g. `H`, `Cl`, `Fe`), followed by an **optional integer count** (default
  1, e.g. `O2`), or
- a **parenthesised group**: `(` + group sequence + `)` followed by an
  optional integer multiplier, e.g. `(SO4)3`. Parentheses **nest** (e.g.
  `K4(Fe(CN)6)`, `Ca(Al(OH)4)2`).

The molar mass is the sum over all parts of `multiplier × Σ mass(element) ×
count`. Whitespace anywhere in the formula is **invalid**. Any violation of
the grammar — unknown element symbol (one not in the masses table), unbalanced
parentheses, a lowercase letter starting a group, a bare multiplier like `12`
with no following groups, an empty string, or any other unexpected character —
makes the row **invalid**.

## Screening and ranking semantics

1. Read every non-empty line of the compounds file. `candidates` = number of
   non-empty lines (this includes lines that are not valid JSON at all).
2. A row is **parsed** iff it is a JSON object whose `"formula"` is a string
   that parses under the grammar above using the given mass table.
   `parsed` = number of such rows; `skipped` = `candidates - parsed`.
3. For each parsed row compute the molar mass `mw` (full precision) and the
   distance `d = round(abs(mw - target), 4)` (**rounded to 4 decimals before
   any comparison**). Keep the row iff `d <= tolerance` — the boundary is
   **inclusive**.
4. Normalisation and score: with `dnorm = round(d / tolerance, 6)` (if
   `tolerance` is `0`, every kept row has `dnorm = 0.0`), and
   `score = round(1 - dnorm, 6)`.
5. Emit one JSON object per kept row to the `--output-jsonl` file with **exactly
   these keys**: `"id"`, `"formula"`, `"molar_mass"` (= `round(mw, 4)`),
   `"distance"` (= `d`), `"dnorm"`, `"score"`. Rows are sorted by ascending
   `distance`, ties broken by ascending `id` (string comparison). One JSON
   object per line; an **empty file if nothing is kept**.
6. Write the `--report` file as JSON with exactly these keys:
   ```json
   {"candidates": <int>, "parsed": <int>, "kept": <int>, "skipped": <int>,
    "target": <float>, "tolerance": <float>}
   ```
   (`target`/`tolerance` echo the screen values as floats.)

## Edge cases the grader probes (hidden inputs follow the same contract)

- **Nested parentheses** and **hydrate parts** with both `·` and the ASCII
  dot, including multi-digit hydrate multipliers (`·12H2O`, `.10H2O`).
- **Invalid rows**: unknown element, unbalanced parentheses, lowercase start,
  embedded whitespace, bare multiplier, empty/missing/non-string formula, and
  even a non-JSON line — all must be counted in `skipped`, never crash.
- **Inclusive tolerance boundary**: a candidate with `d` exactly equal to
  `tolerance` is kept.
- **Ties**: two candidates with the same `d` are ordered by ascending `id`.
- **Exact hit**: a candidate with `d = 0` gets `dnorm = 0.0`, `score = 1.0`.
- **Empty dataset** or **zero kept rows** → empty `ranked.jsonl` and a report
  with `kept: 0` (never a crash).

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/screen.py`)
  on hidden inputs, so do not hard-code the provided file contents or
  filenames.
- Standard library only; no network at verify time.
- Do not modify the provided input files.