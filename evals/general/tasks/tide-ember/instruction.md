# TideEmber — calibrate, filter, and rank observations near a target flux

You are the pipeline engineer for the TideEmber radio survey. Calibration
observations arrive spread over several catalog files, in **mixed flux units**,
and each instrument has its own gain. Your job is to build a reusable selection
program that normalizes every observation to the target unit, keeps only the
ones within tolerance of a target value, ranks them by proximity, and reports
how each value was normalized. The program must work **on any input** that
follows the documented format below — the grader re-runs it unchanged on hidden
inputs.

## Environment

- Working directory: `/app`. It already contains the inputs:
  ```
  /app/sources/            one or more catalog_*.json files (JSON arrays)
  /app/units.json          unit conversion table (see below)
  /app/instruments.json    instrument -> {"gain": <number>} lookup table
  /app/target.json         the selection target
  ```
  Python 3.12 is available as `python3`.
- **Do not modify anything under `/app/sources/` or any of the three `.json`
  input files.**

## Input formats

`/app/sources/` — each `*.json` file contains a JSON **array** of observation
records:

```json
{"obs_id": "ALPHA-000", "instrument": "VLA", "band": "C",
 "flux_density": {"value": 38.2, "unit": "Jy"}}
```

Records may be **malformed** in many ways (see rules); malformed entries are
skipped silently — the program must never crash on them.

`/app/units.json` — object mapping a unit string to the factor that converts a
value expressed in that unit into the reference unit **Jy**:

```json
{"Jy": 1.0, "mJy": 0.001, "uJy": 1e-06, "W m-2 Hz-1": 1e26}
```

`/app/instruments.json` — object mapping instrument name to its calibration
record: `{"VLA": {"gain": 1.02}, ...}`. The **gain** is a multiplicative
correction applied after unit conversion.

`/app/target.json` — `{"property": "flux_density", "unit": "Jy",
"value": <number>, "tolerance": <number>}`. The target value and tolerance are
expressed in the reference unit Jy.

## Deliverables (both required)

1. `/app/flux_select.py` — a runnable Python program with this interface:
   ```
   python3 /app/flux_select.py <sources_dir> <units_json> <instruments_json> <target_json> <output_json>
   ```

2. `/app/ranked.json` — the JSON array your program produces **when run on the
   provided `/app` inputs**:
   ```
   python3 /app/flux_select.py /app/sources /app/units.json /app/instruments.json /app/target.json /app/ranked.json
   ```

## Exact selection / ranking rules

Process every `*.json` file in the sources directory in **sorted filename
order**; within a file process records in array order.

For each record, **skip it silently** (never crash) if any of these holds:

- it is not a JSON object, or `obs_id` / `instrument` is not a string;
- `flux_density` is missing or not an object;
- `instrument` has no entry in the instruments table, or its `gain` is not a
  plain number;
- `flux_density.unit` is not a key of the units table, or
  `flux_density.value` is not a plain number;
- the value is not finite (NaN/Infinity must not appear in output).

Otherwise compute the **normalized value**:

```
value = round(value * units[unit] * gain, 6)
```

(the rounding is to 6 decimal places), the **distance**:

```
distance = round(abs(value - target_value), 4)
```

and keep the record **iff `distance <= tolerance`** (inclusive boundary: a
record exactly at the tolerance is kept).

Each kept record contributes one output element with **exactly these keys**:

```json
{"obs_id": "...", "instrument": "...", "value": <normalized value>,
 "distance": <as computed above>,
 "score": <see below>,
 "normalization": "<unit>->Jy x<factor>; gain <gain>"}
```

- `score = round(1.0 - distance / tolerance, 6)` — the proximity score.
- `normalization` is the reporting string for how the value was normalized:
  the record's original unit, an arrow, `Jy x`, the `repr()` of the float unit
  factor (e.g. `1e-06`), then `; gain ` and the `repr()` of the float gain
  (e.g. `1.02`). Example: `"uJy->Jy x1e-06; gain 0.98"`. Every kept record
  carries this string, even when the unit was already Jy
  (`"Jy->Jy x1.0; gain 1.02"`).
- The output array is sorted by **ascending `distance`**, ties broken by
  **ascending `obs_id`** (string comparison).
- The output is a JSON array written to the given output path. Zero kept
  records means the array `[]`.

Additional parsing rules:

- Only files ending in `.json` in the sources directory are read (sorted by
  filename); a source file that fails to parse as JSON, or is not a JSON
  array, is skipped entirely.
- Booleans are **not** numbers in this contract (`true`/`false` as `value` or
  `gain` means the record is skipped).
- Standard library only; no network access at verify time.
- Nothing may be hard-coded to the provided fixture contents.

## Edge cases the grader probes

- A record whose distance is **exactly** the tolerance must be kept
  (inclusive boundary); one just outside must be dropped.
- Two records with the **same distance** must be ordered by `obs_id`.
- Mixed units (Jy, mJy, uJy, `W m-2 Hz-1`) and per-instrument gains all
  interact; the reported `value` must be the fully normalized one.
- Malformed records of every kind listed above are skipped without crashing.
- A selection where nothing matches yields exactly `[]`.

## Constraints

- The verifier runs your program **unchanged** on hidden inputs that follow
  the same formats.
- Do not modify anything under `/app/sources/` or the three `.json` inputs.
