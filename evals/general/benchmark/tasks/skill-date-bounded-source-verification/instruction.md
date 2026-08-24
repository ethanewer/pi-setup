At `/app/records.csv` there is a CSV with a header row `id,entry_date`. Each `entry_date` is an ISO-8601 calendar date (`YYYY-MM-DD`).

A data source is considered **within date bounds** if its entry date lies in the inclusive window `start = 2024-01-01` to `end = 2024-12-31`.

Write `/app/verify.py` that:
1. reads `/app/records.csv`,
2. marks each record as valid if its `entry_date` is on or after `2024-01-01` and on or before `2024-12-31` (both endpoints inclusive), and invalid otherwise,
3. writes the `id` of each **valid** record, one per line, to `/app/valid_ids.txt`, preserving input order.

For the given file, the valid ids in order are `r1`, `r3`, `r5`, `r6` (records `r2` before the window start and `r4` after the window end are invalid). Use only the Python standard library (`csv`, `datetime`). Run your script so the output file exists.
