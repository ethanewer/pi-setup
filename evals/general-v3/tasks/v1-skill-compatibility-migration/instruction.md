/app/events_v1.jsonl is a JSON-lines file of events in an **older (v1) schema**. The service has moved to a new (v2) schema; you must migrate the records.

Legacy v1 record fields and their new v2 equivalents:

| v1 field  | v2 field            | transformation                                                            |
|-----------|---------------------|--------------------------------------------------------------------------|
| `time`    | `timestamp`         | copied unchanged                                                         |
| `user_id` | `customer`          | value becomes a string prefixed with `user_` (e.g. `7` -> `"user_7"`)     |
| `event`   | `kind`              | copied unchanged                                                         |
| `amount`  | `amount_cents`      | dollars -> integer cents, i.e. `round(amount * 100)`                     |

A v1 record is **invalid** if it is missing any of `time`, `user_id`, `event`, or `amount`; invalid records are skipped entirely (not present in the output).

Write `/app/migrate.py` that reads `/app/events_v1.jsonl` (one JSON object per line), migrates the valid records in their original order using the table above, and writes `/app/migrated.json` as a JSON array of v2 objects. Each v2 object has exactly the four keys `timestamp`, `customer`, `kind`, `amount_cents`.

Then run your script so `/app/migrated.json` is produced. Use only the Python standard library.