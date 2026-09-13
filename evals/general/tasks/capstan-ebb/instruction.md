# capstan-ebb

You are working inside a real upstream open-source project: **bandit**
(`PyCQA/bandit`), the security-oriented static analyser for Python, checked out
at a pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's SQL-injection detector. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the bug
is part of the task.

## Environment

- Python 3.12. The checked-out tree at `/app/src` is the live bandit
  installation: `bandit` is installed editable from `/app/src`, so the `bandit`
  CLI and any `import bandit` resolve straight into this tree and pick up your
  edits immediately. The project's own test dependencies are installed too.
- Outbound network is not available and must not be relied on. Everything needed
  is baked in. Do not `pip install` anything and do not `git fetch`/`git clone`.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`. Your fix lives in the working tree only.

## The bug (user-visible symptom)

Bandit ships a check — test id **B608** — that reports "Possible SQL injection
vector through string-based query construction" whenever it sees an SQL
statement being assembled from strings instead of being parameterised, e.g.:

```python
cur.execute("SELECT * FROM users WHERE id = '%s'" % uid)   # flagged (correct)
cur.execute("INSERT INTO users VALUES ('%s')" % uid)       # flagged (correct)
```

That is the classic injection vector: unsanitised input flows into a query
string, and B608 exists to catch it. In this tree, though, one common writing
style slips through. An INSERT that opens its value list directly after
`VALUES`, **with no space**:

```python
cur.execute("INSERT INTO users VALUES(%s)" % uid)          # NOT flagged — bug
```

is silently scanned without any finding, while the byte-identical statement
with a space after `VALUES`:

```python
cur.execute("INSERT INTO users VALUES (%s)" % uid)         # flagged (correct)
```

is flagged. Both spellings are valid SQL and mean exactly the same thing; both
feed unsanitised input into a query string; both must be reported.

Reproduce it:

```bash
cat > /tmp/values.py <<'EOF'
import sqlite3
conn = sqlite3.connect('app.db')
cur = conn.cursor()
value = "x' OR '1'='1"
cur.execute("INSERT INTO foo VALUES(%s)" % value)
EOF
bandit -q /tmp/values.py
echo $?     # prints 0: nothing found — bug
```

The same file with `VALUES (%s)` prints exit status 1 and a B608 finding. After
a correct fix, the no-space form must also produce exit status 1 with exactly
one B608 finding (Severity: Medium, Confidence: Medium) at the `execute` line.

## Requirements

1. Fix the tree so that B608 reports **both** `VALUES (` and `VALUES(` the same
   way. The finding must be raised for every string-building style the check
   already handles — `%`-formatting, f-strings, `str.format()`, string
   concatenation — case-insensitively, and for statements that span multiple
   lines. The opposite must also stay true: a parameterised query such as
   `cur.execute("INSERT INTO users VALUES(?, ?)", (u, p))` or
   `cur.execute(..., (u, p))` must still produce **no** B608 finding. Do not
   change what the check reports for `SELECT`, `DELETE` or `UPDATE` statements.
2. Everything else must keep working exactly as before: the project's own test
   suites stay green (both the functional tests and the unit tests — see below).
3. The graded tree must be byte-identical to the original except for **the
   single source file where the bug lives**. Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (scratch `.py` files live in `/tmp`,
   never in `/app/src`).
2. **Localise**: B608 decides a string is SQL by matching it against a regular
   expression. Grep the bandit plugin directory (`/app/src/bandit/plugins`) for
   the SQL-injection test to find that matcher, and work out why `VALUES (`
   matches while `VALUES(` does not.
3. **Fix** with the smallest possible change, then prove both directions:
   ```bash
   cd /app/src
   bandit -q /tmp/values.py          # must exit 1 with one B608 finding now
   bandit -q /tmp/values_space.py    # spaced form (VALUES (%s)) must still be flagged
   # parameterised form must stay clean:
   bandit -q /tmp/values_param.py    # must exit 0, no B608
   ```
   and check the project's own tests stay green:
   ```bash
   cd /app/src && python -m unittest tests.functional.test_functional
   cd /app/src && python -m unittest discover -s tests/unit -p 'test_*.py'
   ```
4. Stress the edges: lowercase keywords (`insert into ... values(...)`),
   `executemany`, f-string and `.format()` construction, a statement whose
   string literals span multiple lines, and a parameterised `VALUES(?, ?)`
   query — the first four must be flagged, the last one must not.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the clone holds
  exactly that one commit and nothing else, and that every tracked file except
  the single source file the bug lives in is byte-identical to the pinned
  commit (any other modification, added file or untracked scratch file fails);
- require `/app/summary.md` to exist;
- re-run the reproduction above and require exactly one B608 Medium finding at
  the `execute` line;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, extracted from a successor revision of the tree) into
  the test-suite directories and run the project's own `unittest` on it and on
  the surrounding suites — the whole functional test module and the whole unit
  test suite must pass;
- run three additional bandit scans on inputs the upstream regression test does
  not use — a lower-case `%`-formatted `executemany` file, f-string/`str.format`
  constructions, and a multi-line statement built by implicit string
  concatenation — demanding the `VALUES(` lines produce B608 findings while the
  parameterised control lines stay clean.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.