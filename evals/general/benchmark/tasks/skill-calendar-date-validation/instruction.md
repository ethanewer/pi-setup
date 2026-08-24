In `/app` there is `dates.tsv`: one ISO-8601 date (`YYYY-MM-DD`) per line, 22 lines,
deliberately mixing valid and invalid calendar dates.

Write `/app/validate_dates.py` that implements **calendar date validation**:

- A date is valid iff it satisfies all of:
  - year `Y` in `1..9999`, month `M` in `1..12`, day `D` in `1..31`;
  - `D` does not exceed the number of days in `M` for that year, with February having 29
    days exactly in leap years.
- Leap year rule (Gregorian): `Y` is a leap year iff `Y % 4 == 0` and
  (`Y % 100 != 0` or `Y % 400 == 0`). So `2000` is a leap year, `1900` is not,
  `2024`/`2004`/`2020` are.
- `1582-10-10` is valid under the proleptic Gregorian calendar; `0000-01-01` is invalid
  (year must be ≥ 1).

Run it (e.g. `python3 /app/validate_dates.py`) so that it reads `/app/dates.tsv`, checks
every line, and writes `/app/dates_verified.txt` containing one verdict **per input
line**, in the same order, each on its own line — exactly `VALID` or `INVALID`.

The verifier checks your output against the correct verdicts recomputed from
`/app/dates.tsv` with the rules above.