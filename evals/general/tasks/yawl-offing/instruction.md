# ORM UPDATE..RETURNING returns mislabeled columns after the first execution

## Situation

`/app/src` is a shallow, pinned clone of SQLAlchemy (`https://github.com/sqlalchemy/sqlalchemy`),
checked out at upstream commit `16177b8c73e492e5adaad8f51095f9981831da41` and
installed from that tree in editable (development) mode, so the code you
`import` is exactly the checked-out source at `/app/src/lib/sqlalchemy`. The
interpreter is Python 3.12 with pytest 9.1.1, pytest-xdist 3.8.0 and greenlet
3.5.5 installed, matching what the project's own configuration expects. The
standard library's `sqlite3` provides the database: SQLite supports
`UPDATE..RETURNING` and `DELETE..RETURNING`, so everything the task needs is
already on the machine.

There is **no network** at trial time. `pip` and `git fetch` will not work;
everything you need is baked into the image.

## The bug (user-visible symptom)

The ORM layer lets you take an UPDATE or DELETE statement, attach
`.returning(...)` to ask the database to hand back column values of the
touched rows, and execute it through a `Session`. There is an execution option
`{"synchronize_session": "fetch"}` documented to work with RETURNING: after the
statement runs, the ORM re-reads the affected rows so objects in the session's
identity map reflect the new values.

On this tree there is a shape of that operation that silently returns **wrong
columns** — not wrong values under the right names, but the value of one column
delivered under another column's name — and only on its second use:

- The **first** time you execute a particular ORM `UPDATE` (or `DELETE`)
  statement shape with `.returning(...)`, the returned rows are correct.
- The **second** execution of the same statement *shape* — a new, equivalent
  statement object, executed against the same engine with the same
  `synchronize_session="fetch"` option — returns mislabeled rows: a column
  object (e.g. `row[T.c]`) resolves to a different physical position than the
  same column's string name (`row["c"]`), and the values read back through the
  underlying, Core-level result are exchanged between columns.

Concrete example. A mapped table declared as columns `(id, b, a)` — note
`b` comes *before* `a` in the declaration — is updated with
`.values(b=999).returning(T.id, T.a, T.b)` (returning order `id, a, b`, which
does **not** match the declaration order). Executed twice against the same
engine with `synchronize_session="fetch"`:

- execution 1 (compiled statement put into the cache): `a=20, b=999` — correct.
- execution 2 (served from the compiled statement cache): looking up `T.a`
  returns `999` (the value actually assigned to `b`) and looking up `T.b`
  returns `20` (the value of `a`).

Affected behaviour: any ORM UPDATE or DELETE that (a) uses `.returning()`
whose column order differs from the order the columns are declared on the
mapped table, and (b) is executed with `synchronize_session="fetch"`, returns
mislabeled columns on the second and subsequent executions of the same
statement shape. Statements that do not use `.returning()`, do not use
`synchronize_session="fetch"`, or whose `.returning()` order matches the
table's declared order are unaffected.

### How the symptom shows up (and how it hides)

The corruption lives in the **cursor-level result metadata** of the underlying
Core result object: the map from each returned column to its physical position
in the row. Because of that:

- Row access that goes through cached positional read functions — and the ORM's
  own reprocessing of result rows through the ORM-level `result` object — can
  **mask** the corruption, so do not trust an observation that only reads rows
  through the ORM-level result.
- The deterministic observation is on the raw Core result of the execution
  (`result.raw`): for every returned column, the physical index resolved by
  the *Column object* (`result.raw._metadata._index_for_key(col)`) and the
  physical index resolved by the *string name* (`_index_for_key(name)`) must
  agree. When the bug is present they diverge on the cache-hit execution (the
  second of two executions with the same statement shape on the same engine),
  and the values read back through `result.raw.mappings()` are exchanged.
- Read `result.raw` **before** consuming the ORM-level rows of the same
  execution: consuming the result can close the underlying cursor.

## Your job

Work in the checked-out tree at `/app/src`. Do the following in order.

### 1. Write a failing reproduction first (deliverable: `/app/repro.py`)

Before changing any source code, author your own minimal reproduction of the
symptom described above at `/app/repro.py`. Contract:

- Plain Python 3, runnable as `python3 /app/repro.py` from any working
  directory. No pytest, no command-line arguments, no external files.
- Sets up its own fresh SQLite database (in-memory is fine) and its own
  declarative mapped table with **at least three mapped integer columns whose
  declared order deliberately differs from the `.returning()` order you will
  use** (exactly the shape described above).
- Inserts at least two rows (e.g. four rows with distinct values per column).
- Executes the **same statement shape twice** against the same engine with
  *different parameter values* each time, each execution wrapped in a
  `Session` and each using `execution_options={"synchronize_session": "fetch"}`:
  the first execution populates the compiled statement cache, the second (a
  new, equivalent statement object) is served from it.
- On **both** executions asserts, via `result.raw`:
  - for every column in the `.returning()` clause, the raw metadata index by
    Column object equals the raw metadata index by string name; and
  - the values read back through `result.raw.mappings()` are exactly what the
    UPDATE should have produced (updated value where the statement sets one,
    unchanged values everywhere else).
- Prints what it observes to stdout (one line per assertion failure is fine),
  and **exits 0 if and only if every assertion holds on both executions**,
  non-zero otherwise.
- Must **fail while the bug is present** (on this tree, today: exit non-zero,
  reporting the cache-hit mismatch) and **pass after your fix**. This is the
  graded deliverable the verifier runs against both trees, so it must be
  honest — not special-cased to a print statement or a hardcoded exit code.

Confirm the reproduction fails now, before you change anything.

### 2. Find and fix the bug

Localise the defect in the checked-out tree and make the smallest change that
makes `/app/repro.py` pass, using the project's own test runner to drive and
verify your work. Fix the mechanism, not the reproduction: the same defect is
reachable with other column scrambles, other numbers of columns, a
`.returning()` that names only *some* of the columns, `DELETE` as well as
`UPDATE`, and any number of executions after the first.

### 3. Prove nothing else broke

The project's own regression tests must stay green. From `/app/src`:

```
cd /app/src && python3 -m pytest test/orm/dml -q -p no:cacheprovider
```

The whole directory currently passes (956 passed, a few skipped) at the pinned
commit; keep it that way. You may add your own scratch tests while you work,
but delete anything you add to the tree before you finish — the graded tree is
the pinned commit plus the single source change.

### 4. Write `/app/summary.md`

A non-empty write-up: what the bug was, where you found it, what you changed,
and how you verified the fix.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone at `/app/src` is the deliverable. **Do not add, move, delete or
  rename any file inside the clone; do not modify `.git` (no commits, no
  fetch, no remotes, no rebase); keep the working tree detached at the pinned
  commit.** Your two authored files `/app/repro.py` and `/app/summary.md`
  live **outside** the clone, directly under `/app`. Scratch work belongs in
  `/tmp`. Files you create while investigating (including `__pycache__`
  directories and `.pytest_cache`) must be removed before you finish.
- The verifier requires that exactly **one tracked source file** of the clone
  differs from the pinned commit — the source file where the defect lives.
  It will refuse any other tracked modification, any added or deleted file,
  and any leftover untracked file.
- `/opt/golden`, `/opt/pristine-lib`, `/tests` and `/solution` are
  harness-owned: read them if you like, never modify them.

## What the verifier checks

1. Provenance: `HEAD` is still the pinned commit `16177b8c73e492e5adaad8f51095f9981831da41`,
   the working clone contains exactly one commit object (nothing fetched or
   added), the only modified tracked file is the single source file the defect
   lives in (at least one modification must be present), and `import
   sqlalchemy` still resolves to `/app/src/lib/sqlalchemy`.
2. Deliverables: `/app/repro.py` (executable, per the contract above) and
   `/app/summary.md` exist and are non-empty.
3. Both directions for your reproduction: `/app/repro.py` must exit 0 on your
   repaired tree; run with `PYTHONPATH=/opt/pristine-lib` (a pristine pre-fix
   copy of the tree baked into the image), it must exit non-zero — proving the
   symptom is real in the pre-fix tree and that your reproduction targets it.
4. The project's own upstream regression test for this behaviour — kept out of
   the tree at `/opt/golden/` and planted in by the verifier — must pass, along
   with the rest of `test/orm/dml/test_orm_upd_del_assorted.py`.
5. The project's own `test/orm/dml` suite must still pass.
6. Hidden cases exercising the same code path from inputs the upstream test
   does not use must pass: a four-column table with a different column
   scramble and a two-column `.values()`; a `DELETE` run through three
   consecutive cache hits with a row-count check; and an `UPDATE` whose
   `.returning()` names only a subset of the columns with a two-row
   `id.in_(...)` where clause.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.

Deliverables: the repaired `/app/src`, `/app/repro.py`, `/app/summary.md`.