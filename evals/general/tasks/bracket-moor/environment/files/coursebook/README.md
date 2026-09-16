# coursebook

A small course-registration ledger backed by SQLite. Pure Python standard
library (``sqlite3``), no third-party dependencies. Python 3.10+.

```
python3 -m coursebook init ledger.sqlite
python3 -m coursebook add-student  ledger.sqlite ada@example.org "Ada Lovelace"
python3 -m coursebook add-course   ledger.sqlite CS101 "Intro to Computing" 2
python3 -m coursebook register     ledger.sqlite ada@example.org CS101 2024F
python3 -m coursebook complete     ledger.sqlite ada@example.org CS101 B
python3 -m coursebook roster       ledger.sqlite CS101
python3 -m coursebook usage        ledger.sqlite
python3 -m coursebook history      ledger.sqlite ada@example.org
```

All commands exit `0` on success and `2` on a domain or usage error (message
on stderr). Successful mutations print nothing. The listing commands print a
tab-separated header line followed by one row per entry, always sorted.

## Schema

Three tables: `students` (unique email), `courses` (unique code, positive
seats), and `registrations`:

```sql
CREATE TABLE registrations (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES students(id),
    course_id INTEGER NOT NULL REFERENCES courses(id),
    semester TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'completed', 'dropped')),
    grade TEXT,
    UNIQUE (student_id, course_id)
);
```

## The registration invariant (read this before changing anything)

`registrations` enforces **`UNIQUE (student_id, course_id)`**: a student can
hold at most one registration row per course, whatever that row's status
(active, completed or dropped).

This constraint is deliberate and load-bearing, not a style choice:

- rosters and seat usage derive from registration rows and assume **one row
  per student per course** — a student on a course's roster, one seat consumed
  while the registration is active;
- a recorded grade is per (student, course); with one row the mapping is
  total and unambiguous — there is never a question of "which grade";
- the constraint lives in the **table definition** (not just in the Python
  writer), so the database itself rejects a double booking even for code that
  bypasses the API;
- the tests in `tests/` pin all of the above, including a raw-SQL test that
  expects `sqlite3.IntegrityError` on a duplicate row.

**Known limitation.** There is currently no retake flow: a student who has
already been registered for a course cannot re-enrol for it later. If you add
one, the invariant above — and every test that pins it — must stay intact.

## Tests

```
python3 -m pytest -q tests
```

Run from the repository root. The suite must be green before any change and
must stay green afterwards.