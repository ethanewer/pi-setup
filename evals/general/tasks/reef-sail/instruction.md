# Corrupted CHECK-constraint reflection from SQLite

## Situation

`/app/src` is a shallow, pinned clone of the SQLAlchemy project
(`https://github.com/sqlalchemy/sqlalchemy`), checked out at a specific
upstream revision and installed from that tree in editable (development)
mode: `import sqlalchemy` loads the checked-out Python source directly
(`/app/src/lib/sqlalchemy`). Python 3.12, pytest, pytest-xdist, greenlet
and typing-extensions are installed. The task is designed to be solvable
entirely offline — everything you need is already in the image — and it
does not require any external database (SQLite in-memory is enough).

## The bug (user-visible symptom)

When application code creates a SQLite table that declares several
constraints in one `CREATE TABLE` — in particular a `CHECK` constraint
followed by another kind of constraint clause, such as a `UNIQUE` or
`PRIMARY KEY` constraint — and later reflects the table back, e.g.

```python
inspect(conn).get_check_constraints("mytable")
```

the reflected CHECK constraint is **corrupted**: instead of the pure check
expression (say `"value > 0"`), the dialect returns the check text with a
trailing comma and the beginning of whatever constraint clause came *next*
in the `CREATE TABLE` appended to it. A concrete example observed in the
wild:

```
'((value > 0) AND (value < 100) AND (value != 50))), UNIQUE (value'
```

The pure expression ends at `...!= 50))`; the `, UNIQUE (value` tail is the
next constraint's clause that the reflection swallowed. The stored sqltext
is then no longer the pure check expression, and re-emitting it from the
reflected metadata produces wrong DDL.

Useful detail for reproducing, observed directly in the generated DDL:
SQLAlchemy emits a UNIQUE / PRIMARY KEY / FOREIGN KEY constraint that
carries an explicit name as a `CONSTRAINT <name> UNIQUE (...)` /
`CONSTRAINT <name> PRIMARY KEY (...)` clause, and those boundaries reflect
fine. The corruption appears when the following clause is emitted **bare**
— `UNIQUE (...)`, `PRIMARY KEY (...)`, `FOREIGN KEY(...) REFERENCES ...` —
which is what a constraint declared without a name produces. Constraints
declared alone reflect cleanly, and a CHECK that is the last constraint in
the table reflects cleanly. Reflection of the other constraints (UNIQUE,
PRIMARY KEY, FOREIGN KEY) still works and must keep working after your fix.

## What you need to do

1. **Write your own failing reproduction first.** It is a deliverable and
   the verifier runs it, so make it real:

   Create a plain Python script at `/app/reproduce_check_constraints.py`
   that, when run as `python3 /app/reproduce_check_constraints.py`:

   - builds an in-memory SQLite database with a table whose `CREATE TABLE`
     contains at least one `CHECK` constraint **followed by another kind of
     constraint clause** (`UNIQUE` or `PRIMARY KEY` or `FOREIGN KEY`); the
     easiest dependable shape is a CHECK followed by an UNNAMED `UNIQUE`
     (or `PRIMARY KEY`, or `FOREIGN KEY`), as described above;
   - reflects the constraints back with `sqlalchemy.inspect(...).get_check_constraints(...)`;
   - prints the observed constraint names and sqltext;
   - **exits with status 0 if and only if** every CHECK constraint reflects
     back its exact, pure check expression (no trailing comma, no appended
     clause text) and prints a short confirmation line; otherwise prints the
     corruption it observed and **exits nonzero**.

   The verifier will run your script twice: against the pristine pre-fix
   tree it must fail (nonzero exit) — proving it genuinely catches the
   bug — and against your repaired tree it must pass (exit 0).

2. **Fix the checked-out tree at `/app/src`** so that SQLite
   CHECK-constraint reflection returns the pure expressions in every such
   case: a CHECK followed by `UNIQUE`, `PRIMARY KEY`, `FOREIGN KEY`, a
   named `CONSTRAINT`, or another `CHECK`. The fix must be a change to the
   library source, made in place. Do not change the tests, move the HEAD
   commit, add or remove git remotes, or fetch anything.

3. **Validate with the project's own test runner**, from `/app/src`:

   ```
   cd /app/src && python3 -m pytest test/dialect/test_sqlite.py -q -p no:cacheprovider
   ```

   At the pinned commit this file is green (201 passed, 1 skipped). Keep it
   that way: the verifier re-runs it and it must still pass after your fix.
   Add your own throwaway tests if they help you, but leave them under
   `/tmp` or inside a file you delete before finishing; the final tree must
   show a single modified source file and nothing else.

## What the verifier checks

1. Your reproduction script: fails (nonzero) against a pristine copy of the
   pre-fix tree, passes (exit 0) against your repaired tree.
2. The project's upstream regression tests for this behaviour — the
   `ConstraintReflectionTest` class from the fix revision, extracted at
   image build time into `/opt/golden/test_sqlite.py` — pass against your
   tree.
3. The project's own `test/dialect/test_sqlite.py` (the whole file) still
   passes.
4. Authored hidden cases with constraint shapes the upstream test does not
   use pass: a CHECK followed by a multi-column `UNIQUE`; a CHECK followed
   by a `FOREIGN KEY`; a `PRIMARY KEY` sitting between two CHECK
   constraints; CHECK expressions containing string literals with commas
   and parentheses. All reflected constraints (CHECK, UNIQUE, PRIMARY KEY,
   FOREIGN KEY) must remain complete and correctly named.

## Output contract

- Deliverable 1: `/app/reproduce_check_constraints.py` (Python, directly
  runnable, exit 0 iff reflection is clean, as specified above).
- Deliverable 2: the repaired `/app/src` tree (a single modified source
  file inside the sqlalchemy package; everything else byte-identical to the
  pinned revision).

Do not touch `/opt/golden`, `/tests` or `/solution`.