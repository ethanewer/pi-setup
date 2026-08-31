# Coral-Ledger — read-only release analytics over the port ledger

Coral-Ledger's operations database is **production data under a legal hold**:
the release analytics must be computed without changing a single byte of it.
Your job is to write one self-contained Python program, `/app/solve.py`, that
answers the five release questions from the ledger, and to run it on the
shipped database to produce `/app/answer.json`. All optimization must happen
in the **query layer** (SQL and post-processing in your program); the
supplied database content and structure must remain **byte-for-byte
identical** after your program runs.

## Fixed input

`/app/data/port.db` — a SQLite database with tables:

- `vessels(id, name, flag, klass)`
- `voyages(id, vessel_id -> vessels.id, origin_port, dest_port, depart_date, arrive_date)` — dates as `YYYY-MM-DD`
- `port_calls(id, voyage_id -> voyages.id, port, arrive_ts, depart_ts)` — timestamps as `YYYY-MM-DDTHH:MM:SS`; `depart_ts` may be **NULL** (call still in progress)
- `cargo(id, voyage_id -> voyages.id, bill_of_lading, weight_tons, commodity)`
- `params(key, value)` — holds the analysis window: `window_from` and `window_to` (inclusive dates)

Do not modify `/app/data/port.db`, and do not create or leave any sidecar
files next to it (`port.db-wal`, `port.db-shm`, `port.db-journal`).

## Deliverables (both required)

1. `/app/solve.py` — runnable as:

   ```
   python3 /app/solve.py <db_path> <out_json>
   ```

   It must work on **any** ledger with the same schema (the verifier runs it
   against hidden ledgers with different data, including different
   in-window activity), so derive everything — including the analysis
   window — from the database itself. Do not hard-code table contents.

   The program must open the database **read-only** (e.g. SQLite URI
   `file:<path>?mode=ro`) and must not write to the database file in any
   way: no `UPDATE`/`INSERT`/`DELETE`/`DDL`, no temp tables spilled to disk,
   no pragma changes that touch the file.

2. `/app/answer.json` — the JSON your program produces when run as:

   ```
   python3 /app/solve.py /app/data/port.db /app/answer.json
   ```

## The five release questions (exact output contract)

`answer.json` must have exactly these five top-level keys:

1. `"dwell_by_port"`: object mapping each port that has **at least one
   completed** port call (`arrive_ts` and `depart_ts` both non-NULL) with
   **arrival date inside the window** to the **average dwell in hours** —
   dwell = hours between `arrive_ts` and `depart_ts` — rounded to 2 decimal
   places. Ports with no completed in-window calls are omitted. Keys sorted
   is nice-to-have; content is what matters.
2. `"top_commodity"`: `{"commodity": <name>, "total_tons": <int>}` — the
   commodity with the **largest total `weight_tons` over cargo rows whose
   voyage `depart_date` is inside the window**; ties broken by the
   lexicographically smallest commodity name.
3. `"duplicate_bol"`: `{"bols": <int>, "excess_rows": <int>}` — the number
   of distinct `bill_of_lading` values appearing on **more than one** cargo
   row, and the number of "extra" rows beyond one per such value.
4. `"flag_mix"`: list of `[flag, count]` pairs — for each flag, the number
   of **distinct vessels** of that flag with at least one port call whose
   **arrival date** is inside the window — sorted by count descending, ties
   by flag ascending.
5. `"idle_vessels"`: sorted list of `name` of vessels with **no** port call
   whose arrival date is inside the window.

"In the window" for a date means `window_from <= date <= window_to`
(comparison on the calendar date part of timestamps).

## How you will be graded

1. The verifier fingerprints `/app/data/port.db` (sha256) before and after
   running `/app/solve.py`, and checks that no sidecar journal/WAL files
   appeared — any byte changed fails the run.
2. It compares `/app/answer.json` to the reference answer for the shipped
   ledger.
3. It then copies two **hidden ledgers** (same schema, different data and
   activity), runs your program against each, and compares to their
   reference answers.

No network access; Python 3 standard library only (`sqlite3` is fine).
