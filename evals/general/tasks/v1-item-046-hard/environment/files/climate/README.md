# Item-046 (hard) — Dual-file climate QC migration

Author a complete Python-3 port of `legacy_station.py` (a Python 2 program)
that joins two monthly climate tables, computes annual metrics, per-station
climatology, a linear trend (modern mode) and a per-station data-quality report.

## Files in this environment

- `temps.tsv` — header `station year T1..T12` (monthly temps).
- `precip.tsv` — header `station year P1..P12`; **may be missing
  (station, year) rows that exist in temps.tsv** (here station `D25`, year `2003`
  is missing from precip).
- `legacy_station.py` — the Python 2 source.

## Contract

1. `merged.tsv` — every **matched** (station, year) row, columns
   `station year T1..T12 P1..P12`, temps/precip rounds `%.2f`.
2. `annual_means.tsv` — sorted `(station, year)`, columns
   `station year Tmean Ptot Wet`: Tmean = mean(12 temps),
   Ptot = sum(12 precip), Wet = #(precip > 50.0), formats `%.6f`/`%.6f`/`%d`.
3. `station_clim.tsv` — per station (sorted): `station n climatology`,
   `n` = number of matched years, `climatology = floor(cum/float(n))/100`
   in **legacy** mode and `(cum/n)/100` in **modern**; `cum = Σ round(Tmean*100)`.
4. `trend.tsv` — **modern mode only**, per station (sorted):
   `station slope` OLS of Tmean on year, `%.6f`.
5. `qc.tsv` — per station (sorted): `station n_years min_year max_year
   missing` where `missing` counts years in `[min_year, max_year]` with no **precip**
   record.

## Python-3 CLI (must match)

```
python3 /app/migrate.py --temps T.tsv --precip P.tsv --output OUT_DIR [--mode legacy|modern]
```

`legacy` and `modern` must agree on `merged.tsv`, `annual_means.tsv`, `qc.tsv`;
`station_clim.tsv` must differ exactly by the floor artefact; `trend.tsv` written
only by `modern`.

## Regression harness (deliverable)

```
python3 /app/regress.py --legacy-out L_DIR --modern-out M_DIR
```

prints one line per file: `<file>: IDENTICAL` or `<file>: DIFFER (expected floor)`,
exits 0 when `merged.tsv`, `annual_means.tsv` and `qc.tsv` identical, `station_clim.tsv`
differs, and `trend.tsv` only in the modern dir. (stdlib + subprocess only.)