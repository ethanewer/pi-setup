# Pinevale Dental — Contact-Sync Conflict Report

You are the platform engineer for **Pinevale Dental**, whose staff contacts are
synced to three devices (`laptop`, `phone`, `tablet`). Each device periodically
uploads its copy of every contact field, and the uploads often disagree. Your
job is to build a reusable program that turns a raw sync dump into a structured
**conflict report**. The verifier re-runs your program on brand-new hidden
inputs, so it must implement the rules below exactly — not just fit the
provided file.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/contact_sync.json`. Python 3.12 is available as `python3`.
- **Do not modify `/app/contact_sync.json`.**

## Deliverables (both required)

1. `/app/sync_report.py` — a runnable Python program with this interface:
   ```
   python3 /app/sync_report.py <input.json> <output.json>
   ```
   It reads a sync dump and writes the conflict report to the given output
   path. It must work on **any** input conforming to the format below.

2. `/app/conflict_report.json` — the report your program produces when run on
   the provided fixture:
   ```
   python3 /app/sync_report.py /app/contact_sync.json /app/conflict_report.json
   ```

## Input format

`<input.json>` is a JSON object of the shape:

```json
{
  "records": [
    {"user": "amara", "field": "phone", "device": "phone",
     "value": "555-0101", "synced_at": "2026-04-01T09:00:00Z"},
    ...
  ]
}
```

- Every record is an object with exactly the keys `user`, `field`, `device`,
  `value`, `synced_at` (all strings; `synced_at` is an ISO-8601 UTC timestamp
  that compares correctly as a plain string).
- `device` is one of `laptop`, `phone`, `tablet`.
- Records may repeat (same user/field/device/value/synced_at appearing twice)
  and may appear in any order.

## Merge rules (implement exactly)

Group all records by their `(user, field)` pair.

- A **conflict** exists for a `(user, field)` pair if and only if the group
  contains **at least two records whose `value`s differ**. A group with one
  record, or with several records that all share one value, is **not** a
  conflict (repeated identical uploads are normal).
- **Winner record** of a conflicting group: the record with the
  lexicographically **greatest** `synced_at`. If several records tie on
  `synced_at`, prefer higher device priority: `laptop` > `phone` > `tablet`.
  If a tie still remains (same `synced_at` and same device), the record
  appearing **earliest in the input file** wins.
- The winning record's `value` is the chosen value.

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "users_affected": <int>,
  "total_conflicts": <int>,
  "conflicts": [
    {
      "user": "<user>",
      "field": "<field>",
      "sources": [
        {"device": "...", "value": "...", "synced_at": "..."},
        ...
      ],
      "winner": "<chosen value>",
      "winner_device": "<device of the winning record>"
    },
    ...
  ]
}
```

- `conflicts` lists every conflicting `(user, field)` pair in the order the
  pair's **first** record appears in the input file.
- `sources` contains **every** record of the group (all devices, including
  duplicates and outvoted values), in input-file order, each as
  `{device, value, synced_at}`.
- `winner` is the chosen value; `winner_device` is the winning record's
  device.
- `total_conflicts` must equal EXACTLY `len(conflicts)`.
- `users_affected` is the number of **distinct** users that have at least one
  conflict.
- An input with no conflicting pairs yields
  `{"users_affected": 0, "total_conflicts": 0, "conflicts": []}` — including
  the completely empty dump `{"records": []}`.

## Constraints

- The verifier runs your program **unchanged** on hidden inputs that follow
  the same format (including tie-breaking cases, duplicate rows, groups with
  three or more distinct values, and empty dumps), so do not hard-code to the
  provided file.
- No network access; standard library only.
- Do not modify `/app/contact_sync.json`.
