# Rowan Statute — annual customs declaration generator

## Context
You work on the compliance desk of an import/export firm. The firm must file
an annual customs declaration. Raw transaction records for the declaration
period are provided; you build a generator `build_declaration.py` that
validates the records, aggregates the valid ones per (direction, partner
country, commodity), exempts low-value aggregates, and emits the declaration
plus a validation report.

## Visible inputs (already in `/app`)
- `/app/transactions.csv` — one transaction per line. The FIRST line is a
  header row and is skipped. Columns in order:
  `txn_id,date,direction,partner_country,commodity_code,value_eur,quantity_kg`.
- `/app/codes/countries.json` — `{"codes": ["DE", ...]}`: list of valid
  partner-country codes (ISO2-like). A country is valid if it is a member of
  this list, matched EXACTLY (case-sensitive).
- `/app/codes/commodities.json` — `{"codes": {"271019": {"unit": "kg"}, ...}}`:
  valid commodity codes. Each entry MUST be a JSON object whose `"unit"` field
  is a non-empty string; an entry that is not such an object makes the code
  unusable (treated as unknown).
- `/app/params.json` —
  `{"declaration_period": {"start": "YYYY-MM-DD", "end": "YYYY-MM-DD"},
    "exemption_threshold_eur": {"dispatch": <EUR>, "arrival": <EUR>}}`.
  The two thresholds are exact euro amounts with at most 2 decimal digits.
  `declaration_period` is informational metadata only — it does NOT filter
  rows.

## Deliverables (all under /app)
1. `/app/build_declaration.py` — CLI: `python3 build_declaration.py <workdir>`
   where `<workdir>` contains the four inputs above (`transactions.csv` at its
   root, plus `codes/` and `params.json` inside it). The script writes
   `declaration.csv` and `validation_report.json` INTO `<workdir>`. Exit code 0
   on success; exit code 1 with a message on stderr if the argument is missing
   or a required input is missing/unreadable.
2. `/app/declaration.csv` — the declaration produced by running the generator
   on the visible workdir `/app` (the visible inputs live directly under
   `/app`, so the command is `python3 build_declaration.py /app`).
3. `/app/validation_report.json` — the validation report for the same run.

## Pipeline (exact)
1. **Validation.** Read every data row after the header; ignore blank lines.
   - A row whose field count is not exactly 7 is rejected with the single
     reason `MALFORMED_ROW` (no other reasons are considered for it).
   - For a 7-field row, ALL failures are collected as reasons, checked in this
     exact order:

     | reason code | applied when |
     |---|---|
     | `INVALID_DIRECTION` | `direction` is not exactly `dispatch` or `arrival` (case-sensitive) |
     | `UNKNOWN_COUNTRY` | `partner_country` is not a member of countries.json |
     | `UNKNOWN_COMMODITY` | `commodity_code` is not a key of commodities.json, or its entry is not an object with a non-empty string `unit` |
     | `INVALID_DATE` | `date` is not exactly `YYYY-MM-DD` for a real calendar date (e.g. `2024-02-30`, `2024/03/01`, `2025-13-99` all fail) |
     | `INVALID_VALUE` | `value_eur` does not match `^\d+(\.\d{1,2})?$` (non-negative decimal with at most 2 digits after the point; empty, negative, thousands separators, exponents, stray spaces all fail) |
     | `INVALID_QUANTITY` | `quantity_kg` does not match `^\d+(\.\d{1,3})?$` (non-negative decimal with at most 3 digits after the point) |

   - Field values are matched exactly as they appear — no whitespace trimming.
   - `txn_id` is never validated; it is opaque and used only for reporting.
   - A row with any reason is REJECTED and excluded from aggregation. Only rows
     with zero reasons are VALID.

2. **Aggregation (valid rows only).** Group by the key
   `(direction, partner_country, commodity_code)` and for each key sum:
   - `value_eur` using EXACT integer cents arithmetic: convert each value to an
     integer number of cents with exact decimal arithmetic (e.g. `12.30` ->
     1230 cents), sum the integers, never float. All values have at most 2
     decimals so the conversion is exact.
   - `quantity_kg` as exact integer milli-kg (thousandths, e.g. `1.5` -> 1500
     milli-kg), summing integers.

3. **Exemption.** Keep only aggregates whose summed value in cents is **>=**
   the threshold for that direction (the threshold is converted to cents with
   exact decimal arithmetic). An aggregate exactly AT the threshold IS
   included; strictly-below aggregates are exempt and omitted.

4. **`declaration.csv`.** Header line exactly:
   `direction,partner_country,commodity_code,value_eur,quantity_kg`
   then one line per retained aggregate, sorted ascending in C-locale byte
   order by `(direction, partner_country, commodity_code)`. `value_eur` is
   written with EXACTLY 2 digits after the point (e.g. `822.75`, `500.00`);
   `quantity_kg` with EXACTLY 3 digits after the point (e.g. `150.000`, `3.000`).
   The header line is written even when no aggregates are retained.

5. **`validation_report.json`.** An object `{"rejected": [...]}` with one entry
   `{"txn_id": "...", "reasons": ["..."]}` per rejected row; the `reasons`
   array lists every reason in the check order above. Entries are sorted
   ascending by `txn_id` string; when two entries share the same `txn_id` they
   keep their original file order (stable sort). The list is empty when nothing
   is rejected. The verifier compares parsed values, so any whitespace layout
   is acceptable (the reference writes a single line, e.g.
   `{"rejected":[{"txn_id":"D301","reasons":["INVALID_DIRECTION"]}]}`).

## Constraints
- Pure Python 3 stdlib (`csv`, `json`, `datetime`, `decimal`). No network
  access, no extra packages, no randomness, no timestamps, no absolute paths
  inside the outputs. Outputs must be fully deterministic.

## How the grader probes it
- The verifier independently recomputes the declaration and the validation
  report from the raw inputs and compares them against `/app/declaration.csv`
  and `/app/validation_report.json`.
- It then EXECUTES `python3 /app/build_declaration.py <workdir>` on a copy of
  the visible workdir and on several HIDDEN workdirs with different country
  lists, commodity tables, thresholds and edge shapes (aggregates exactly at
  the threshold, duplicated txn_ids including rejected duplicates, an all-
  invalid file, and an all-valid-but-exempt file), comparing each output
  against its own recomputation. Any mismatch -> reward 0. Hardcoding the
  visible outputs cannot pass, because the hidden workdirs differ.
- Whole verification must finish quickly; per-run timeout 300 s.