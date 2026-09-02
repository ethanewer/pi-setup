# Umber Ridge Capital — capital reconciliation export

Umber Ridge Capital runs a monthly capital-reconciliation. Every month the same
liquidity records are exported, in several different formats, from three
downstream systems. You must consolidate them into one canonical schema, then
cross-check the consolidated book against the reported regional grand totals to
catch the single inconsistent figure, and finally export the reconciled numbers
to a company spreadsheet grid through the provided CellGrid API.

You produce **three deliverables**:

1. `/app/reconcile.py` — a **generic, re-runnable** exporter script.
2. `/app/mart.npy` — the unified parsed dataset (a NumPy structured array).
3. `/app/sheet.jsonl` — the JSON-Lines transcript of the API cell writes that
   populate the sheet grid.

## Inputs (read-only — never modify)

The current run's source files live in **`/app/sources/`**:

| file | format | contents |
|------|--------|----------|
| `/app/sources/clients.json` | JSON | object `{"records": [ ... ]}` |
| `/app/sources/deals.csv` | CSV | header row + data rows |
| `/app/sources/ledger.parquet` | Parquet | table with 0+ rows |
| `/app/sources/region_report.json` | JSON | `{"report_id": str, "grand_totals": {region: number}}` |

The four canonical region codes are `NORTH`, `SOUTH`, `EAST`, `WEST`.
`region_report.json` always lists **exactly these four** grand totals.

## Canonical schema

Every logical record across the three sources maps to one row with these fields:

| canonical field | type | meaning |
|-----------------|------|---------|
| `client_id` | int | unique record id |
| `name` | string | full display name |
| `region` | string | source-provided region label (kept verbatim) |
| `balance_value` | float | monetary figure |

### Field mapping (differently-named but synonymous fields)

`clients.json` — each object in `records` uses:
`client_id`, `first_name`, `last_name`, `branch`, `vp_balance`.
- `client_id` → `client_id`; `name = first_name + " " + last_name`;
  `region = branch`; `balance_value = vp_balance`.

`deals.csv` — column header: `deals_id,holder,territory,capital_deal`.
- `client_id = deals_id`; `name = holder`; `region = territory`;
  `balance_value = capital_deal`.

`ledger.parquet` — columns: `cid,label,zone,val`.
- `client_id = cid`; `name = label`; `region = zone`;
  `balance_value = val`.

You must map **all three** sources; missing any source or any field yields an
incomplete dataset.

## Cross-check rule

The `mart` rows are grouped by **canonical** region: for each of the four
regions, `computed_total[region] = sum of balance_value over mart rows whose
region equals that code`. Only the four canonical codes participate; any other
region label is stored in the mart verbatim but contributes to no region total.

Compare each `computed_total` against the corresponding
`grand_totals[region]` with a small float tolerance (`1e-6` is fine). **Exactly
one** region is inconsistent — its reported `grand_totals` value is the single
anomalous figure. Identify that region.

## Deliverable 1 — `/app/reconcile.py`

A standalone, re-runnable script runnable on **any** matching source directory
(the verifier will re-run it on different hidden input sets), with an exact CLI:

```
python3 /app/reconcile.py <SOURCES_DIR> <OUT_DIR>
```

It must:
- read `<SOURCES_DIR>/clients.json`, `.../deals.csv`, `.../ledger.parquet`,
  `.../region_report.json`;
- write `<OUT_DIR>/mart.npy` and `<OUT_DIR>/sheet.jsonl` (creating OUT_DIR if
  needed).

`numpy` and `pyarrow` are installed and available. Do not hardcode specific
values from the visible data — the script must generalize.

### `mart.npy`

Save a NumPy structured array (shape `(n,)`) with dtype fields, in order:

```
client_id   i8
name        U48
region      U16
balance_value f8
```

one row per parsed record. Row order is not checked, but the full set of
`client_id`s and every record's `name`, `region`, `balance_value` must be exact
(`region` stays verbatim, e.g. an unusual label keeps its value).

### `sheet.jsonl`

Populate a sheet grid **through the CellGrid API**: the module `gridkit` is at
`/app/gridkit` and exposes a class `CellGrid` with
`set_cell(address, value)` and `export(path)`. Import it as
`from gridkit import CellGrid`. `set_cell` validates the address form
(`<COL><ROW>` with 1 or more uppercase letters and a positive integer row, e.g.
`"B4"`, `"C7"`) and writes only scalar values; malformed addresses raise. Call
`export(path)` to write the transcript.

The grid layout is fixed. Region rows:

```
NORTH row 2
SOUTH row 3
EAST  row 4
WEST  row 5
```

For each region row, at that row's cells:

- `A{row}` — the region code, e.g. `"NORTH"`.
- `B{row}` — that region's computed total (float).
- `C{row}` — that region's reported `grand_totals` figure (float).
- `D{row}` — verdict string: `"OK"` if the region reconciled,
  `"MISMATCH"` if it is the inconsistent one.

And the reconciliation summary cell:

- `F2` — the **reported grand total of the inconsistent region** (the single
  anomalous figure, float).

Exactly one region must carry `"MISMATCH"`, and it must be the same region
that fails the reconciliation comparison.

`export` writes one JSON object per line to the transcript
(`{"cell": "B2", "value": 3700.5}`). That file **is the deliverable**
`sheet.jsonl`. Put it at `<OUT_DIR>/sheet.jsonl`.

## Edge cases you MUST handle (hidden inputs probe these)

- In **any** source, numeric fields may be given as **strings** (e.g.
  `"1234.50"`) — coerce to float/int (via `int()`/`float()`), never crash.
- `deals.csv` may contain **blank lines** and quoted/embedded commas — split on
  the leading fields by position with Python's `csv` reader and skip empty rows.
- Any one of the three sources may contain **zero records** — an empty parquet
  table / empty array / header-only CSV. Skip it; the dataset still parses.
- A record may carry a **non-canonical region** label (e.g. `"ZONE-9"`) — it
  still appears in the mart with its `region` kept verbatim, but is excluded
  from region totals and is a danger to the sheet (such a row never affects the
  sum cells or the mismatch flag).
- All monetary comparisons are cent-exact floats; use `1e-6` tolerance.
- `region_report.json` always has exactly the four canonical codes, and exactly
  one region is inconsistent.

## Constraints

- Do not modify `/app/sources/**`, `/app/gridkit/**`.
- Deliverables go to the exact paths `/app/reconcile.py`, `/app/mart.npy`,
  `/app/sheet.jsonl`; the visible run is
  `python3 /app/reconcile.py /app/sources /app`.
- Everything the verifier needs must run from a fresh container via that CLI, so
  keep `reconcile.py` free of absolute paths other than the fixed `/app/sources`
  and `/app/gridkit` install and the `SOURCES_DIR` / `OUT_DIR` arguments.