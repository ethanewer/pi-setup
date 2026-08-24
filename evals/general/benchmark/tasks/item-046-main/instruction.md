# Item-046 (medium) — Python 2 → Python 3 climate migration

A legacy climate data-processing program, `legacy_climate.py`, was written for
Python 2 and runs **only** under Python 2. Your job is to migrate it to a
Python-3 program that **preserves the legacy input/output contract**, while
separating *purely syntactic* migration from *behavioral* changes that Python 3
introduces, and proving the port is faithful.

## Files already in the container

- `/app/climate/legacy_climate.py` — the Python-2 source you must port.
  Read it carefully; it contains classic Python-2 constructs (`print`
  statements, binary-mode file reading with explicit `.decode('ascii')`,
  and the historical integer-division artefact described below).
- `/app/climate/temps.tsv` — a sample monthly climate table
  (stations × years × 12 monthly temps + 12 monthly precipitations).
- `/app/climate/README.md` — the full data-format and output-contract spec
  (input layout, exact output schemas, float formatting, and the legacy
  integer-division artefact). **Read it fully before coding.**

## The migration task

Create `/app/migrate.py`, a Python-3 program with this CLI:

```
python3 /app/migrate.py --input IN.tsv --output OUT_DIR [--mode legacy|modern]
```

which must reproduce, for any valid input file:

- `annual_means.tsv` — per (station, year): `Tmean`, `Ptot`, `Wet` (sorted by
  station then year; `%.6f` / `%d` formatting; header included).
- `station_clim.tsv` — per station: `n` and `climatology` with header.
- `trend.tsv` — **modern mode only**: per-station OLS slope of `Tmean` vs year.

Two behavioural subtleties you MUST handle:

1. **The floor-division artefact (behaviour change, not syntax).** The legacy
   code computes `cum` as a scaled integer and divides by the integer year
   count. Under Python 2, `cum / n` floors; under Python 3, `int/int` gives an
   exact float. Your port must implement **both** semantics:
   - `--mode legacy`  → reproduce the historical *floored* climatology
     (integer division),
   - `--mode modern`  → exact floating-point climatology.
   The two modes must therefore produce *different* `station_clim.tsv` values
   (unless the division happens to be exact), while `annual_means.tsv` must be
   identical in both modes.

2. **Syntax migration.** Fix every Python-2-only construct. Do not silently
   change numeric behaviour in the process.

## What to do (stages)

1. Read `README.md` and `legacy_climate.py`.
2. Write `/app/migrate.py` (pure Python 3, stdlib only — no third-party deps).
3. Run it on the bundled sample for both modes, e.g.:

   ```bash
   cd /app && python3 migrate.py --input climate/temps.tsv --output out_legacy --mode legacy
   cd /app && python3 migrate.py --input climate/temps.tsv --output out_modern --mode modern
   ```

4. **Compare legacy vs modern outputs** (the "differential" step): confirm
   `annual_means.tsv` is byte-identical between the two modes, while
   `station_clim.tsv` differs by the documented artefact. Also sanity-check a
   couple of `Tmean` values by hand.
5. Write `/app/differential.md`, a short report (3–8 lines) that explicitly
   separates the changes you made into (a) *syntax-only* fixes and (b)
   *behaviour-handling* decisions (with a one-line justification each).

## Deliverables / success criteria

- `/app/migrate.py` implements the CLI above and runs under Python 3.
- `/app/differential.md` exists and separates syntax vs behaviour.
- The verifier will generate a **fresh** deterministic input table, run your
  `migrate.py` in both modes, and compare every output file byte-for-byte
  against a reference implementation of the same contract:
  - `annual_means.tsv` must match in both modes,
  - `station_clim.tsv` must match in both modes (legacy = floored, modern =
    exact),
  - `trend.tsv` (modern) must match.
- Do not modify `legacy_climate.py` or `temps.tsv`.