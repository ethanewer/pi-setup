# An avoidable extra query when `Session.get()` is called with `with_for_update=False`

## Context

You are working on a real checkout of the SQLAlchemy project, version 2.1.0b2,
at `/app/src`. It is a genuine upstream git working tree pinned to a specific
commit; the code is exactly what the project ships, except that it is missing a
behaviour improvement that upstream later made. Nothing has been modified and
no regression was seeded.

The project is already installed in *editable* mode, so `import sqlalchemy`
resolves to `/app/src/lib`: any edit you make to the source tree is picked up
immediately, no reinstall needed. `pytest` 9.1.1 and `pytest-xdist` are
installed. The default database for the project's own test suite is an
in-memory SQLite, so the tests run with no external server. **There is no
network access in this environment.** `git` works inside `/app/src` (the clone
is shallow and pinned; treat it as read-only history — you will not move the
pinned commit).

## The reported symptom

An application uses `Session.get()` to look up a row by primary key, and it
passes the keyword argument `with_for_update=False` to say "no row locking
wanted" (this is the default meaning of the flag). When the requested object
has *already been loaded* into the session's identity map — for example because
the same object was fetched moments earlier in the same transaction — the
application still observes a real, avoidable `SELECT` hitting the database.

The same call *without* the flag, or with the flag passed explicitly as `None`,
does **not** hit the database: the session short-circuits to the already-loaded
object and issues no query at all. So an explicitly-`False` locking flag
silently defeats an optimisation that `None`/omitted preserves. There is no
error message and no wrong result — just one extra `SELECT` per lookup against
an object that is already in memory. A user noticed the overhead because their
application emits a measurable amount of redundant database traffic.

Your job: (1) write a reproduce script that demonstrates this behaviour, and
(2) repair the source so the unnecessary query is gone while the project's own
test suite for `Session` behaviour keeps passing.

## Deliverables

1. `/app/src/repro_issue.py` — a **standalone** Python script that reproduces
   the symptom on the unfixed tree. Contract, exactly:

   - uses the installed sqlalchemy (plain `import sqlalchemy`; no path hacks),
   - creates an in-memory SQLite engine and a mapped table with an integer
     primary key, inserts one row, and opens a `Session`,
   - loads that row once into the session via `Session.get(...)` so the object
     is in the session's identity map, and counts the database statements that
     are emitted **after** that initial load (a `before_cursor_execute` event
     listener is the natural way; ignore DDL and the insert),
   - then calls `Session.get(<pk>, with_for_update=False)` for the same already
     loaded object in the same session,
   - prints a single summary line and exits:
       * exit status **0** and the line `OK` when the flagged call causes
         **zero** additional statements (i.e. the bug is absent),
       * exit status **1** and a line `extra selects: N` (N = the number
         measured) when it causes one or more additional statements (i.e. the
         bug is present).

   The verifier runs this script on both sides of your work: against an
   untouched pre-fix copy of the sources (it must exit 1 there) and against
   your repaired tree (it must exit 0 there). Write it so it works from any
   working directory and needs no arguments.

2. The repaired source tree at `/app/src`: make the reported behaviour correct
   so the redundant query disappears. The project's own ORM test suite for
   sessions — `test/orm/test_session.py`, ~212 tests — must pass in full after
   your change, exactly as it does at the pinned commit. Do not modify anything
   under `test/` (the verifier runs the upstream copies of those files itself).

## Checking your work

From `/app/src`:

```bash
python3 /app/src/repro_issue.py        # exits 1 while the bug is present
python3 -m pytest test/orm/test_session.py -q   # 212 passed at the pinned commit
```

When you have fixed the bug, the script must exit 0, and the suite must still
be green. Diagnose, don't guess: follow what the session actually executes and
find and repair the source-level cause of the behaviour difference.

## Constraints

- Only edit code under `/app/src`. Do not modify anything under `/opt` (those
  are the verifier's own reference copies) or outside the tree.
- `repro_issue.py` must be self-contained and use only the standard library
  plus sqlalchemy (and its dependencies, e.g. sqlalchemy's own event API).
- There is no network: everything you need is already in the image. The fix
  does not require installing anything.