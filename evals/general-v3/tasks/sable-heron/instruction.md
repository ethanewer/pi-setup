# Reconcile the Halvern Benefits directory exports

The people-operations team at **Halvern Benefits** syncs employee directory
fields from two systems: the recruiting CRM and the payroll platform. Each
system periodically drops a JSON export of field updates, and the two
frequently disagree. You must build a merge tool that reconciles the exports
and emits a structured **conflict report**. The verifier reruns your program on
hidden export pairs, so the tool must implement the documented rules exactly —
not merely fix the provided files.

## Environment

- Working directory: `/app`. It already contains the input fixtures
  `/app/crm_export.json` and `/app/payroll_export.json`. Python 3.12 is
  available as `python3`.
- **Do not modify `/app/crm_export.json` or `/app/payroll_export.json`.**

## Deliverables (both required)

1. `/app/merge_dirs.py` — a runnable Python program with this interface:
   ```
   python3 /app/merge_dirs.py <crm_json> <payroll_json> <report_json>
   ```
   It reads the two exports and writes the conflict report to the given output
   path. It must work on **any** input pair conforming to the contract below.

2. `/app/conflict_report.json` — the report your program produces **when run on
   the provided fixtures**:
   ```
   python3 /app/merge_dirs.py /app/crm_export.json /app/payroll_export.json /app/conflict_report.json
   ```

## Input format

Each export file is a JSON **array** of record objects:

```json
{ "user": "j.doe", "field": "work_email", "value": "j.doe@halvern.io", "synced_at": "2026-04-02" }
```

- `user` and `field` are strings naming the account and the directory field.
- `value` is a string (the synced value for that field).
- `synced_at` is a `YYYY-MM-DD` string (lexicographic order = chronological
  order). If a record omits `synced_at` (or it is not a string) it is treated as
  `"0000-00-00"`.

**Normalization.** For each export, reduce it to one record per distinct
`(user, field)` pair:

- Skip any array element that is not a JSON object.
- Skip any record whose `user` or `field` is missing or not a string, or whose
  `value` is missing or not a string.
- Among multiple records for the same `(user, field)` **within one export**,
  keep the one with the greatest `synced_at`; on a tie, keep the **last** such
  record in array order.

An export file that is missing, unparseable JSON, or not a JSON array yields an
empty normalization (the program must still run).

## Merge semantics (implement exactly)

- A `(user, field)` pair is a **conflict** iff, after normalization, it has a
  record in **both** exports and the two `value`s differ. Pairs present in only
  one export, or agreeing across exports, are not conflicts.
- The **winner** of a conflict is the value from the export whose kept record
  has the strictly greater `synced_at`. On a `synced_at` tie (including the
  `"0000-00-00"` default), **payroll wins** (it is the system of record).

## Required report JSON

The output file must be valid JSON with exactly these three keys:

```json
{
  "pairs_considered": <int>,
  "total_conflicts": <int>,
  "conflicts": [
    {
      "user": "<user>",
      "field": "<field>",
      "entries": [
        { "export": "crm", "value": "<crm value>", "synced_at": "<crm synced_at>" },
        { "export": "payroll", "value": "<payroll value>", "synced_at": "<payroll synced_at>" }
      ],
      "winner": "<chosen value>",
      "winner_export": "<\"crm\" or \"payroll\">"
    }
  ]
}
```

- `pairs_considered` = number of distinct `(user, field)` pairs present in at
  least one export after normalization.
- `conflicts` is sorted by `user`, then `field` (plain string ordering).
- `entries` lists the contributing source values, **crm first, then payroll**,
  using each export's kept record (its winning value and `synced_at`).
- `winner` is the chosen (merged) value; `winner_export` names the export it
  came from.
- `total_conflicts` must equal `len(conflicts)`.
- If there are no conflicts, `conflicts` is `[]` and `total_conflicts` is `0`.

## Edge cases the grader probes (hidden inputs)

- Exports that disagree in both directions: a **newer CRM record overriding
  payroll**, and payroll winning by **newer or tied** `synced_at`.
- Duplicate `(user, field)` rows inside one export (older first and last), plus
  records with `synced_at` omitted.
- Malformed array elements: non-objects, missing `user`/`field`/`value`,
  non-string `value` — all skipped silently.
- Agreements across exports (never reported), solo pairs (never reported), and
  empty arrays / unparseable export files (treated as empty).
- An empty result: `pairs_considered` may be 0 and `conflicts` must be `[]`.

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/merge_dirs.py`)
  on hidden export pairs, so do not hard-code the provided fixtures.
- Standard library only; no network access at verify time.
- Do not modify `/app/crm_export.json` or `/app/payroll_export.json`.
