# Keystone Courier — deployment-plan artifact pack

Keystone Courier routes delivery units to service requests each operating day.
The ops team needs a **single self-contained program** that turns a fleet-request
input into a complete, deterministic "deployment plan" artifact pack with exact
output formats. You must author `/app/solve.py` and run it against the committed
input so every artifact (including `/app/answer.json`) is produced in `/app`.

## Deliverables (exact paths)

1. `/app/solve.py` — a standalone Python 3 program (executable, `chmod +x`) that
   implements every rule below and is runnable on **any** fleet-request CSV.
2. `/app/answer.json` — produced by running `/app/solve.py` (see below).

`solve.py` must do the real work: parse the CSV, solve the per-zone selection
optimization, compute the objective, and write every artifact. It must work from
any working directory and accept zero, one, or both of these arguments:

```
python3 /app/solve.py [--input <csv>] [--output <dir>]
```

Defaults: `--input /opt/keystone/requests.csv`, `--output /app`.

The verifier will re-run your program on the committed input **and** on hidden
inputs (each with a `--output` temp dir) and compare every produced artifact
against a canonical reference. Any artifact missing, extra, mis-ordered, or
with the wrong content fails.

## Input schema

A CSV with a header row and these **exact** column names (case-sensitive):

```
route_id,zone,slot,units,cost
```

- `route_id`: non-empty string, **unique across the file**.
- `zone`: non-empty string naming a deployment zone.
- `slot`: integer in the inclusive range `0..47` (half-hour time slot of a day).
- `units`: positive integer (number of demand units).
- `cost`: positive integer (cost per unit; `value = units * cost`).

### Row validity (edge handling — hidden cases probe this)

A row is **invalid** and must be silently **skipped** (never crash the program)
when any of the following holds:

1. a required column is missing or cannot be parsed as an integer (`slot`,
   `units`, or `cost` non-numeric);
2. `route_id` or `zone` is empty/whitespace-only;
3. `slot` is outside `0..47`; `units <= 0`; or `cost <= 0`;
4. the `route_id` already appeared **earlier** in the file (duplicate — the
   later occurrence is skipped).

All remaining rows are **valid**.

## Rules (identical for every valid row set)

Let `capacity(zone) = 15 + len(zone)` where `len` is the number of characters
in the zone name.

Group valid rows by `zone`. For **each zone independently**, solve a **0/1
knapsack**: choose a subset of that zone's rows maximizing
`sum(units * cost)` subject to `sum(units) <= capacity(zone)`.
**Tie-break:** among all subsets with the maximum total value, choose the one
whose sorted tuple of `route_id` values is **lexicographically smallest**.

- A chosen row's decision is `RUN`; a valid row not chosen is `HOLD`.
- The **zone optimum** is that zone's maximum total value.
- The **objective** (a non-negative integer) is the sum of all zone optima.

Rows may be enumerated by brute force (zone sizes are small) — the exact method
does not matter as long as the chosen subset and objective are the deterministic
optimum above.

## Artifacts to emit (written under `--output DIR`)

All file names, namespaces, and on-disk layouts below are exact. Paths under
`transformed/` are created automatically. All files end with exactly one
trailing newline.

### 1. `plan_records.csv` (required schema + column order)
Columns, in this exact order: `route_id,zone,slot,units,cost,value,decision`
One row per **valid** row in **input order**, with `value = units * cost` and
`decision` one of `RUN`/`HOLD`.

### 2. `decisions.txt` (decision flags + objective, exact format)
```
objective=<objective>
<route_id>=<RUN|HOLD>
<route_id>=<RUN|HOLD>
```
First line `objective=<objective>`; then one line per valid row, sorted by
`route_id` ascending.

### 3. `objective.txt` (optimal objective persisted, exact format)
Exactly one line: `objective=<objective>`.

### 4. `final_report.csv` (exact final column set AND order)
Columns in this exact order: `zone,planned_units,opt_value,served`
One row per **distinct valid zone** sorted by zone name ascending, where
`planned_units` = sum of `units` of that zone's `RUN` rows, `opt_value` = that
zone's zone optimum, `served` = count of `RUN` rows in the zone.

### 5. `transformed/<zone>.csv` (transformation output files, exact columns)
For each distinct valid zone, one file named `<zone>.lower()` + `.csv`. Columns
in this exact order: `route_id,slot,units,value,decision`. Rows sorted by
`slot` ascending then `route_id` ascending.

### 6. `answer.json` (stable, schema-exact JSON)
Exactly this structure (values your computed results; key order is free, values
and types must match exactly):
```json
{
  "schema_version": 1,
  "objective": <objective>,
  "plan": [
    {"route_id": "...", "zone": "...", "slot": <int>, "units": <int>,
     "cost_unit": <int>, "decision": "RUN"}
  ]
}
```
`plan` lists only `RUN` rows, sorted by `zone` ascending, then `slot` ascending,
then `route_id` ascending. `cost_unit` is the row's `cost`. This is the
`/app/answer.json` deliverable.

### 7. `schedule.xlsx` (spreadsheet cells via openpyxl at exact addresses)
Build the workbook with **openpyxl's cell API** (do not hard-code a pre-built
file). Two sheets:

- Sheet **`Schedule`**:
  - `A1` = `DEPLOYMENT_SCHEDULE`
  - Row 2 header: `A2=route_id B2=zone C2=slot D2=units E2=cost_unit F2=value`
  - Rows `3..(2+n)` = the `RUN` plan (same order as `answer.json` `plan`), each
    cell a scalar (numeric cells numeric, not strings).
  - After the data rows, one blank row, then at row `L = n + 4`:
    `A<L>` = `OPTIMAL_OBJECTIVE` and `B<L>` = the objective (numeric).
- Sheet **`Flags`**:
  - `A1` = `route_id`, `B1` = `flag`
  - Rows from 2: every **valid** row sorted by `zone`, then `slot`, then
    `route_id`; `A` = route_id, `B` = `RUN`/`HOLD`.

Here `n` is the number of `RUN` plan rows.

## Constraints

- Do not modify `/opt/keystone/requests.csv`.
- Do not use the network. `openpyxl` and `pandas` are preinstalled.
- `solve.py` must be executable and must exit `0` on success; it must never
  crash on malformed input (invalid rows are skipped, never raise).
- Keep all files readable. Do not hardcode the committed input's rows — the
  program must work for any fleet-request CSV (the hidden cases feed fresh,
  grouped, tie-laden, boundary, and malformed inputs).