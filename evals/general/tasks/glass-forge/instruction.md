# Roster Reconciliation — Fernwave Logistics

The HR systems team at **Fernwave Logistics** feeds three independent record
stores into one merged roster. The stores disagree with each other constantly,
and the merge tooling is your job today. Everything happens in `/app` with
Python 3.12 available as `python3`.

You must build a **reusable** reconciler: the verifier re-runs your program,
unchanged, on brand-new roster inputs that follow the same contract below, so
your logic must be fully general — never hard-code to the provided file.

## Input format

`/app/roster.json` is a JSON document:

```json
{ "records": [ {"user": "...", "field": "...", "source": "...", "value": "..."}, ... ] }
```

- Every record carries exactly the four string keys `user`, `field`,
  `source`, `value`.
- A record whose `source` is not one of the three known sources below is
  **ignored entirely** (it contributes nothing, ever).
- A record missing any of the four keys, or carrying a non-string value in any
  of them, is ignored entirely.
- Records appear in a specific **file order**; that order matters (see rules).

### Source priority

Only these three sources exist, with this fixed priority (highest first):

1. `directory`
2. `payroll`
3. `badge`

## Reconciliation rules (implement exactly)

Group the contributing records by their `(user, field)` pair.

- A pair is a **conflict** when the records contributing to it contain **two
  or more distinct `value` strings**. Pairs with zero or one contributing
  record, or where all contributing records agree on the value, are not
  conflicts.
- The **winner** of a conflicting pair is the `value` of the contributing
  record with the **highest-priority source** (`directory` beats `payroll`
  beats `badge`). If several contributing records share that top source, the
  one appearing **last in file order** among them wins.

## Deliverables (both required)

1. `/app/reconcile.py` — a runnable Python program:

   ```
   python3 /app/reconcile.py <records_json> <output_json>
   ```

   It reads the records file and writes the conflict report to the given
   output path. It must work on any input conforming to the format above.

2. `/app/conflict_report.json` — the report your program produces on the
   provided `/app/roster.json`:

   ```
   python3 /app/reconcile.py /app/roster.json /app/conflict_report.json
   ```

## Output report schema

Valid JSON with exactly these keys and shapes:

```json
{
  "total_conflicts": <int>,
  "conflicts": [
    {
      "user": "<user>",
      "field": "<field>",
      "sources": [
        {"source": "<source>", "value": "<value>"}
      ],
      "winner": "<chosen value>"
    }
  ]
}
```

- `conflicts` contains **every** conflicting `(user, field)` pair, ordered by
  the **first appearance** of that pair in the input file order.
- `sources` lists each **distinct** `(source, value)` combination among the
  pair's contributing records, ordered by first appearance. (Two records may
  share a source but differ in value; both then appear, with the same
  `source` string and their own `value`.)
- `winner` is the chosen value as defined above (a conflicting pair always
  has at least one contributing record, so `winner` is always that record's
  value).
- `total_conflicts` must equal exactly `len(conflicts)`.

## Edge cases probed by the grader

- **Empty records list** → `{"total_conflicts": 0, "conflicts": []}`.
- **No conflicts at all** (agreements, single records, unknown sources) but a
  non-empty input → empty `conflicts`, `total_conflicts` 0.
- **Same-source disagreements** (two `payroll` rows for one pair with
  different values) — a real conflict; the later row wins.
- **Unknown-source rows** interleaved with real ones — ignored, they can
  neither create nor resolve a conflict, and never appear in `sources`.
- **Priority inversion by file order** — a higher-priority record appearing
  *after* lower-priority ones still wins.
- **Multiple pairs for the same user** and **multiple users** — each
  `(user, field)` pair is judged independently.
- Records with extra keys, missing keys, or non-string values — ignored.

## Constraints

- Do not modify `/app/roster.json` (the verifier checks its integrity).
- No network access at verify time; standard library only.
- The verifier runs `/app/reconcile.py` unchanged on hidden inputs; do not
  hard-code file names or the visible contents.
