# Duplicate result column names must raise a psycopg error, not a bare ValueError

## Situation

`/app/src` is a shallow, pinned clone of the psycopg project
(`https://github.com/psycopg/psycopg`), checked out at an upstream commit that
contains the bug described below, and the `psycopg` and `psycopg_pool`
packages are installed from that tree into site-packages **non-editably** (a
regular `pip install`, not `-e`). This non-editable layout matters: the
monorepo has a top-level `psycopg/` subproject directory, which shadows an
editable install when Python runs from the repo root, so the installed,
importable copy is the one under site-packages and it is taken *from the tree
at build time* — a copy, not a live view.

Python 3.12, pip, pytest 9.1.1, and libpq 17.11 (loaded by psycopg through
ctypes; no PostgreSQL server is installed or needed) are present. The task
is fully solvable with what is already in the image: no download, `pip
install` from an index, or `git fetch` is needed or expected. Note that the
trial may have outbound network access; using it to look up or fetch the
upstream fix would defeat the purpose of this exercise, and the verifier
rejects any clone from which the upstream fix commit has become reachable.

## The bug

When a query result set contains two columns with the same name — which
happens naturally in joins, e.g. `SELECT f.id, b.id FROM film f JOIN book b
ON ...` — and the connection uses the **namedtuple row factory**, the row
factory lets a plain `ValueError` from the Python standard library escape
instead of raising a psycopg exception. User code that catches psycopg errors
therefore does not see it. Duplicate column names are a data-shape problem and
should surface as `psycopg.errors.DataError`, exactly like the other
data-shape errors the library raises.

The expected behaviour after the fix: building a namedtuple row type from a
duplicate column set raises `psycopg.errors.DataError`. The message must state
that a namedtuple row cannot be created and carry the details behind the
standard `ValueError` (e.g. the offending field name). The fix must not change
any behaviour for result sets whose column names are not duplicated.

## Reproducing the failure

```
cd /tmp && python3 /app/probe_row_factory.py
```

prints where the error comes from. The equivalent direct probe:

```
cd /tmp && python3 -c "from psycopg import rows; rows.namedtuple_row(...)"
```

Run these from `/tmp` (or any other directory that is not the repo root).

## What you need to do

Fix the bug **in the checked-out tree at `/app/src`** so that duplicate result
column names surface as `psycopg.errors.DataError` (a subclass of
`psycopg.errors.Error`, so code catching psycopg exceptions sees it), with a
clear error message, and nothing else changes.

The tree is the deliverable, but the code that Python imports lives in
site-packages as a copy of the tree. After you edit the tree, refresh the
installed copy — the verifier will do the same refresh against your tree, so
the edit must be in the tree, not only in site-packages:

```
python3 -m pip install --force-reinstall --no-deps --no-build-isolation --no-index /app/src/psycopg
```

Self-check loop, in this order:

1. `cd /tmp && python3 /app/probe_row_factory.py` — before the fix it reports
   a standard-library `ValueError`; after the fix it must report
   `psycopg.errors.DataError` with `[psycopg error: True]`.
2. `cd /tmp && python3 -m pytest /opt/golden/test_rows.py::test_make_nt_duplicate_names -q`
   — the project's own regression test for this behaviour, extracted at image
   build time from the upstream fix commit. (Run just that node id: the other
   tests in the file are connection-bound and are not wired up in this
   offline image.)
3. `cd /app/src && python3 -m pytest tests/test_rows.py -q` — the project's
   own existing row-factory test file must stay green (the database-backed
   tests skip on this image, which is upstream's own convention).

## Constraints

- Do not rely on the network; everything needed is installed already, and
  fetching or looking up the upstream fix is against the intent of the task.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier asserts that the working tree is still at the pinned commit,
  that no other tracked files were modified, that the fix touches only the
  minimal source surface (no new files inside the installed package), and that
  the answer was not fetched: the upstream fix commit must not become
  reachable from the clone.

## What the verifier checks

1. The tree is still at the pinned commit, the upstream fix commit is not
   reachable from the working clone, no extra tracked files were changed, the
   minimal source file is the only thing modified, and no new files appeared
   inside the installed package.
2. The change to the source tree actually implements the fix: the added code
   must intercept the standard-library `ValueError` and raise a psycopg
   `DataError` — a comment or a no-op edit is not a fix.
3. The verifier refreshes the installed package from your tree
   (`pip install --force-reinstall --no-deps --no-build-isolation --no-index
   /app/src/psycopg`) so a tree-only fix is what gets scored.
4. The project's upstream regression test for this behaviour passes, and the
   fixture files under `/opt/golden` are unchanged from the build-time copies
   (their checksums are pinned).
5. The direct repro (`python3 /app/probe_row_factory.py` from `/tmp`) reports
   a psycopg error, and the project's own existing row-factory test file
   still passes.
6. The verifier itself generates duplicate-column inputs the upstream test
   never uses (duplicates that only collide after the factory's identifier
   mangling, duplicates buried in random-length column lists, and the
   non-duplicate path) and checks the installed package end to end, without
   going through pytest.
7. Hidden cases over inputs the upstream test does not use pass: duplicate
   names that only collide after the factory's identifier mangling, other
   encodings, duplicates buried in longer column lists, the error message
   wording, and the duplicate-name failure flowing through the row factory the
   way a real join result would, with the non-duplicate path demonstrably
   unchanged.

Deliverable: the repaired `/app/src` tree.