# Climate Station Analyzer — migration contract

This directory contains a data-processing program for monthly climate normals at
surface weather stations. It was written in **Python 2** and must run under
**Python 3** while preserving its input/output contract.

## Input format

A tab-separated table `temps.tsv` with one header line followed by one row per
(station, year):

```
station	year	T1 T2 ... T12	P1 P2 ... P12
```

- `station` : short string code (e.g. `A01`).
- `year`    : 4-digit year.
- `T1..T12` : monthly mean temperatures (degrees, may be negative).
- `P1..P12` : monthly precipitation totals (mm).

## Legacy behaviour (Python 2 reference)

The legacy program, `legacy_climate.py`, computes:

1. **Annual measures** (every station-year row, sorted by `(station, year)`):
   - `Tmean` = mean of the 12 monthly temps  (`sum/12.0`, exact float)
   - `Ptot`  = sum of the 12 monthly precip totals
   - `Wet`   = integer count of months where precipiton total > 50.0 mm

   written as `annual_means.tsv`:
   ```
   station	year	Tmean	Ptot	Wet
   ```
   with `Tmean` and `Ptot` formatted `%.6f` and `Wet` as `%d`.

2. **Per-station climatology** (one row per station, sorted by `station`):
   - `n` = number of years for the station
   - `climatology` = mean of that station's annual `Tmean` values.

   **Historical artefact:** the legacy code computes a *scaled* integer
   accumulator `cum = sum(round(Tmean*100))` and then divides
   `scaled = cum / n`. Under Python 2, `cum / n` with two `int` operands is
   **floor** division, so `climatology = floor(cum/n)/100` — the fractional
   part below 0.01 is truncated. A naive Python-3 port (where `int/int` yields
   an exact float) silently changes these values. The `legacy` mode MUST
   reproduce the floored values; the `modern` mode must use exact float
   division.

   written as `station_clim.tsv`:
   ```
   station	n	climatology
   ```

3. **Modern-only trend** (`modern` mode): per-station ordinary least-squares
   slope of `Tmean` vs `year`:
   ```
   station	slope
   ```
   `slope = num/den` with `num = sum((x-xbar)*(y-ybar))`, `den = sum((x-xbar)^2)`,
   formatted `%.6f`. Requires numpy-free pure Python (ok under Python 3).

## Sanity reference (sample only — do not hardcode)

For the bundled `temps.tsv`, the first annual row is A01/2005 and the very
first Tmean comes out just below 25, but you must NOT bake in any absolute
values: the verifier will re-run on a fresh dataset.

## CLI contract for the migrated Python-3 program

Write `/app/migrate.py` so that:

```
python3 /app/migrate.py --input IN.tsv --output OUT_DIR [--mode legacy|modern]
```

reproduces EXACTLY the above formats, in every mode, for ANY valid input file.
Both modes must produce `annual_means.tsv` and `station_clim.tsv`;
`--mode modern` must additionally produce `trend.tsv`. `station_clim.tsv`
must differ between modes exactly according to the floor division artefact
described above.