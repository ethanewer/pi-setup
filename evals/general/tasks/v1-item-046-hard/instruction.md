# Item-046 (hard) — Python 2 → 3 climate QC migration

`legacy_station.py` is a Python-2 climate-station analyzer. Port it to
Python 3 as `/app/migrate.py` with **no third-party packages**, preserving
the IO contract below exactly.

## Environment files

- `temps.tsv` — header `station year T1..T12` (monthly temperatures).
- `precip.tsv` — header `station year P1..P12` (monthly precip). May be **missing rows**
  that exist in `temps.tsv` (here: station `D25`, year `2003`).
- `legacy_station.py` — the Python 2 source.

## Contract

1. `merged.tsv` — every **matched** (station, year): columns
   `station year T1..T12 P1..P12`; values `%.2f`.
2. `annual_means.tsv` — sorted `(station, year)`, columns
   `station year Tmean Ptot Wet`:
   - `Tmean` = mean of the 12 temps (`sum/12.0`),
   - `Ptot` = sum of the 12 precip values,
   - `Wet` = count of months with precip > 50.0 (integer).
   `Tmean`/`Ptot` `%.6f`, `Wet` `%d`.
3. `station_clim.tsv` — per station (sorted): `station n climatology`, where
   `n` = number of matched years and `climatology = (cum / n)/100` in
   **legacy** mode, `(cum / n)/100` in **modern** mode; `cum = Σ round(Tmean*100)`.
   The **legacy** value is the Python-2 integer-division artefact (`cum // n`) and the
   two modes must genuinely differ (unless the sum divides evenly).
4. `trend.tsv` — **modern only**, per station (sorted): `station slope` OLS slope of
   Tmean versus year: `slope = num/den`, `num = Σ(x-xbar)(y-ybar)`,
   `den = Σ(x-xbar)²`; `%.6f`.
5. `qc.tsv` — per station (sorted): `station n_years min_year max_year missing`,
   where `missing` = number of years in `[min_year, max_year]` having NO **precip**
   record (i.e., quality control on the precip file).

## CLI (Python 3)

```
python3 /app/migrate.py --temps T.tsv --precip P.tsv --output OUT_DIR [--mode legacy|modern]
```

`legacy` and `modern` must agree on `merged.tsv`, `annual_means.tsv`,
`qc.tsv`; `station_clim.tsv` must differ by exactly the floor artefact;
`trend.tsv` must exist only in modern mode.

## Regression harness

```
python3 /app/regress.py --legacy-out L_DIR --modern-out M_DIR
```

prints, per file: `<file>: IDENTICAL` or `<file>: DIFFER`, exits 0 iff
`merged.tsv`, `annual_means.tsv`, `qc.tsv` identical, `station_clim.tsv`
differs, and `trend.tsv` only in the modern dir. (stdlib + subprocess only.)