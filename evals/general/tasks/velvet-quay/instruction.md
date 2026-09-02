# Meridian charter-ledger as-of audit

Meridian Charters keeps its contract ledger as a JSON-lines file. Contracts
change over time via dated **amendments**, so every question about the ledger
is answered **as of a fixed reference date**. You will build the audit program.
Work in `/app`. **Do not modify** `/app/charters.jsonl` or `/app/audit.txt`,
and never read `/tests`.

## Deliverables (both required)

1. `/app/audit.py` — a runnable Python program with this interface:
   ```
   python3 /app/audit.py <charters.jsonl> <audit.txt> <output.json>
   ```
   It must work on **any** input conforming to the contract below (the grader
   re-runs it unchanged on hidden ledgers).
2. `/app/audit.json` — the output your program writes for the provided
   `/app/charters.jsonl` and `/app/audit.txt`:
   ```
   python3 /app/audit.py /app/charters.jsonl /app/audit.txt /app/audit.json
   ```

## Input formats

`audit.txt` is plain text and contains the reference date:

```
as_of=YYYY-MM-DD
```

`charters.jsonl` has one JSON object per line. Blank lines are skipped
silently. Each well-formed record has:

```json
{
  "charter_id": "CH-042",
  "vessel": "Auriga",
  "signed_on": "YYYY-MM-DD",
  "start_on": "YYYY-MM-DD",
  "end_on": "YYYY-MM-DD" | null,
  "terminated_on": "YYYY-MM-DD" | null,
  "amendments": [ {"field": "...", "value": ... , "effective_on": "YYYY-MM-DD"}, ... ]
}
```

- `end_on: null` means open-ended (no fixed end).
- `terminated_on: null` means not terminated.
- A line is **malformed** if it is not valid JSON, not a JSON object, or fails
  schema validation: `charter_id` must be a non-empty string, `vessel` a
  non-empty string, `signed_on`/`start_on` valid `YYYY-MM-DD` dates, and
  `end_on`/`terminated_on` either `null` or valid `YYYY-MM-DD` dates.
  Malformed lines are counted but otherwise ignored. A missing or non-list
  `amendments` is treated as `[]`.

## As-of semantics (exact — the grader probes these boundaries)

**Amendment application.** An amendment applies as of the reference date `D`
if and only if `effective_on <= D` (an amendment effective exactly on `D`
applies). For each field, the winning amendment is the one with the **latest**
`effective_on <= D`; ties are broken by the **later position** in the
`amendments` list. A winning amendment with `"value": null` **clears** the
field (sets it back to null). Amendments to fields other than `start_on`,
`end_on`, `terminated_on` (e.g. `signed_on`) are ignored, as are amendments
with a malformed `effective_on` or a malformed (non-null, non-date) `value`.
Unapplied amendments never matter. The as-of field values are the base values
with the winning amendments applied.

**Classification against `D`:**

- **active** — using the as-of field values — if **all** of:
  - `signed_on <= D` (the charter exists by then),
  - `start_on <= D` (it has commenced),
  - `end_on` is null **or** `D <= end_on` (the end date is **inclusive**:
    still active on its end date),
  - `terminated_on` is null **or** `D < terminated_on` (termination is
    **exclusive**: on the termination date itself it is no longer active).
- **pending** — if it is not active and `signed_on <= D` but the as-of
  `start_on > D` (signed but not yet commenced). Note the as-of `start_on`
  (after amendments) decides both classes.
- otherwise (expired/lapsed/terminated/future) the charter is excluded from
  every list.

## Required output JSON

Exactly these keys:

```json
{
  "as_of": "YYYY-MM-DD",
  "active_ids":    ["CH-...", ...],
  "active_count":  0,
  "pending_ids":   ["CH-...", ...],
  "open_ended_ids":["CH-...", ...],
  "by_vessel":     {"<vessel>": <active count>, ...},
  "malformed":     0
}
```

- `active_ids`, `pending_ids`, `open_ended_ids`: sorted lexicographically,
  no duplicates.
- `open_ended_ids`: active charters whose as-of `end_on` is null.
- `by_vessel`: vessel -> number of **active** charters, keys sorted
  (vessels with zero active charters are omitted).
- `malformed`: number of malformed lines, regardless of dates.
- `as_of` echoes the reference date.

## Edge cases the grader probes

- Amendment effective exactly on `D` applies; one day later does not.
- Two amendments of the same field: the later-effective one wins once both
  are in effect.
- `end_on == D` → active; `terminated_on == D` → not active.
- Amendments that move `start_on` into the future make a charter pending;
  clearing `terminated_on` (value null) revives a terminated charter;
  clearing `end_on` makes it open-ended.
- Retro-active amendments (effective_on in the past) apply normally.
- Future-signed charters (`signed_on > D`) appear in no list.
- Malformed lines (bad JSON, bad schema, bad dates) are counted in
  `malformed` and otherwise ignored; blank lines are skipped silently.
- An empty ledger yields empty lists, `active_count: 0`, `by_vessel: {}`,
  `malformed: 0`.

## Constraints

- Standard library only; no network access.
- Do not hard-code the visible ledger contents or the visible as-of date.
