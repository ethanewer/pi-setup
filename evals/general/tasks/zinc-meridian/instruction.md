# Screen the apothecary formulary by molecular-weight proximity

The Meridian Apothecaries' Guild keeps a formulary of candidate compounds in
`/app/compounds.json`, an atomic-mass lookup table in
`/app/atomic_masses.json`, and a screening target in `/app/target.json`. You
must build a reusable screening program that parses each compound's molecular
formula, computes its molecular weight from the lookup table, keeps only the
compounds whose weight lies within tolerance of the target, ranks them by
proximity, and writes a JSON report — including a normalization report of how
the input set was processed. The program must work **on any input** that
follows the documented format below, not just on the provided files.

## Environment

- Working directory: `/app`. It already contains `/app/compounds.json`,
  `/app/atomic_masses.json` and `/app/target.json`. Python 3.12 is available
  as `python3` (standard library only; no network).
- **Do not modify** the three supplied input files.

## Deliverables (both required)

1. `/app/screen.py` — a runnable Python program with this interface:
   ```
   python3 /app/screen.py [--compounds FILE] [--masses FILE] [--target FILE] [--output OUT]
   ```
   (defaults: `/app/compounds.json`, `/app/atomic_masses.json`,
   `/app/target.json`, `/app/formulary.json`). It must work on any inputs
   conforming to the contract below.

2. `/app/formulary.json` — the report your program produces **when run on the
   provided inputs**:
   ```
   python3 /app/screen.py
   ```

## Input formats

- `atomic_masses.json`: a JSON object mapping **element symbols** to mass
  values, e.g. `{"H": 1.008, "C": 12.011, ...}`. Symbols follow the usual
  `X` or `Xx` capitalization.
- `target.json`: `{"descriptor": "molecular_weight", "target": <number>,
  "tolerance": <number>}`.
- `compounds.json`: a JSON **array** of objects
  `{"id": <str>, "name": <str>, "formula": <str or null>}`.

## Formula grammar (parse exactly this; anything else is a rejection)

```
formula := term ('.' term)*          # dot = hydrate separator
term    := INT? group+               # optional leading multiplier for the term
group   := ELEMENT INT?              # e.g. "Cu", "H2"
         | '(' formula-fragment ')' INT?   # parenthesised group, possibly nested
```

- `ELEMENT` is a symbol from the **masses table** (`[A-Z][a-z]?`), followed by
  an optional integer count (1 when absent). An element symbol **not present
  in the masses table** is a rejection (the lookup is authoritative).
- `INT` counts are positive integers; a count of `0` is a rejection.
- Examples: `C8H9NO2`, `Mg(NO3)2`, `CuSO4.5H2O`, `KAl(SO4)2.12H2O`,
  `Ca(Al(OH)4)2`. The multiplier before `(` or after `.` multiplies every atom
  inside/after it.
- Unbalanced parentheses, empty terms, unexpected characters, lowercase
  fragments (`c6h6`), or an **absent/empty/non-string `formula` field** are
  all rejections. A rejected compound never crashes the program.

## Descriptor computation

For a compound whose formula parses to `{element: count}`:

```
molecular_weight = round(sum(mass[element] * count), 4)
```

The masses table is the single source of truth; never use your own values.

## Filtering, ranking and output

- `distance = round(|molecular_weight - target|, 4)`.
- Keep a compound **iff** `distance <= tolerance` (inclusive boundary: a
  compound exactly on the edge is kept).
- Sort the kept compounds by **ascending `distance`**, ties broken by
  **ascending `id`** (lexicographic string compare).
- `score = round(1 / (1 + distance), 6)`.

`OUT` must be valid JSON with exactly these keys:

```json
{
  "descriptor": "molecular_weight",
  "target": <float>,
  "tolerance": <float>,
  "matches": [
    {"id": "...", "name": "...", "formula": "...",
     "molecular_weight": <float>, "distance": <float>, "score": <float>},
    ...
  ],
  "report": {
    "rows_in": <int>,        // compounds read
    "rows_parsed": <int>,    // formulas that parsed successfully
    "rows_rejected": <int>,  // rows_in - rows_parsed
    "rejected_ids": ["..."], // ids of rejected rows, sorted ascending
    "matched": <int>         // length of matches
  }
}
```

An empty compounds array yields `"matches": []` and an all-zero report. A
target far from every compound also yields `"matches": []` with an intact
report.

## Edge cases probed by hidden inputs

The verifier re-runs your program unchanged on hidden inputs, so it must
handle all of the following correctly:

- **different targets/tolerances** and different compound sets;
- compounds **exactly on the tolerance boundary** (kept);
- **ties** in distance (id tie-break);
- **rejections**: unknown elements (possibly against a *different, reduced*
  masses table passed via `--masses`), malformed syntax, missing formula
  fields;
- **deep parentheses and hydrate dots with multipliers**;
- **zero matches** and an **empty compounds array** — never crash, always
  emit the full schema.

## Constraints

- Do not hard-code the provided file contents.
- No network access; Python standard library only.
- Do not modify `/app/compounds.json`, `/app/atomic_masses.json` or
  `/app/target.json`.