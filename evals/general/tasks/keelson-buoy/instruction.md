# CargoOps — repair the corrupted inventory figures (keelson-buoy)

You are the database operator for **CargoOps**, a marine cargo consolidator.
At **03:17 UTC on 2025-01-10** a botched automated sync wrote garbage over
part of the `positions` table in the `cargoops` database. The bad job has
been stopped. **Read `/app/README.md` first** — it is the incident report
and tells you exactly which records in this container are intact and
trustworthy.

## Environment

- Ubuntu 24.04 container with **PostgreSQL 16** installed. The single
  cluster is managed by `/opt/cargoctl/pgctl.sh` (subcommands
  `up`, `ready`, `start`, `stop`, `restart`). The container may boot with
  the cluster stopped: run `/opt/cargoctl/pgctl.sh up` before anything
  else (idempotent; safe to run repeatedly) and leave the cluster running.
- The database is `cargoops`, reachable at
  `postgresql://ops@127.0.0.1:5432/cargoops` (local trust auth, no
  password). The role `ops` owns it.
- The table `positions` is the live inventory: one row per cargo lot,
  keyed by `position_id`. **One of its columns** now holds corrupted
  values. Every other piece of data in the table is intact and must remain
  exactly as it is.
- `/app/backups/cargoops_base_20241130.sql` is a plain-SQL dump of
  `positions` as it stood on **2024-11-30 00:00 UTC** — before the
  corruption and before several legitimate changes that happened later. It
  is part of the incident evidence: **do not alter it**.
- The `cargoops` database still contains everything else needed to
  re-derive the damaged figures. Nothing has been deleted, truncated, or
  reset; all such history is in the database itself.
- No network access. Everything you need is on disk or in the database.

## Deliverable

Write **`/app/repair.py`** — a self-contained Python 3 tool (standard
library + `psycopg2`, which is installed). It must be runnable as:

```
python3 /app/repair.py DSN BACKUP_SQL
```

- `DSN` — a `postgresql://` connection string for the target database.
- `BACKUP_SQL` — path to a pg_dump-style plain-SQL snapshot of the
  `positions` table, same format as the file in `/app/backups/`.

The tool connects, determines which cells are damaged by reconciling the
live table against the intact records (the snapshot and the database's own
change history — see the README), computes the correct values, and applies
the minimal change: only the damaged cells of the overwritten column of the
live inventory table.

## Output contract (what the verifier asserts, main case and hidden cases)

The verifier runs your tool, then compares the final database against its
**pre-run state** (which it recomputes itself from the scenario records):

1. Every row's value in the overwritten column equals the correct value
   derivable from the intact records — no exceptions, no approximations.
2. The table has exactly the same rows, in the same row set, as before
   (no inserts, no deletes, no truncation, no drop, no re-creation from
   the snapshot).
3. Every other column is **bit-identical** to the pre-run state — same
   values, same types, same column inventory, nothing renamed or added.
4. The change-history table is untouched.

So any destructive or over-broad statement — dropping or truncating the
table, an unscoped `DELETE`, re-importing the snapshot wholesale (it is
stale by design and reverts valid later changes), overwriting more than
the damaged cells, rewriting history — is automatically wrong. The repair
is expected to be a single minimal `UPDATE`.

The tool must also:

- be **idempotent** — running it twice changes nothing the second time;
- depend only on its two command-line arguments (no hard-coded data
  values, paths to `/app`, or assumptions about specific rows/sums);
- **not** modify the snapshot file, the README, or any shipped artifacts;
- exit non-zero if it cannot satisfy the contract.

## Hidden instances

The same `/app/repair.py` will later be executed against several
additional databases that reuse this exact schema and the same type of
corruption but **different data**: different row sets, different change
history, different sentinel/seal rows, a different snapshot file (its path
is passed as `BACKUP_SQL`), and a different mix of which cells were
damaged. Your tool must repair all of them from the data alone — nothing
may be hard-coded from the visible instance.

Run your tool against the production instance yourself and confirm the
database satisfies the contract before finishing. Leave `/app/repair.py`
in place — it is the delivered artifact.