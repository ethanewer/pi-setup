# Fix: flake8 dies before checking anything when `$HOME` does not exist

You are working on a real checkout of **flake8** (PyCQA's Python style and
lint tool) from 2022, at `/app/src`. The checkout is installed editable into
this image's Python 3.12 environment together with the project's own
era-pinned dependencies: `pycodestyle 2.9.1`, `pyflakes 2.5.0`,
`mccabe 0.7.0`, and `pytest 7.4.4`, all already present.

There is **no network access** here. Do not try to `pip install`, upgrade, or
fetch anything; everything the task needs is already in the image, and the
checkout's git history is deliberately shallow.

## The bug, as a user would report it

> When I run flake8 in an environment whose `HOME` environment variable points
> to a directory that does not exist, flake8 dies with a raw Python traceback
> **before checking a single file** — no lint output at all. This happens for
> system accounts in containers (e.g. Debian's `nobody` user, which runs with
> `HOME=/nonexistent`), cron jobs with no real home directory, and services
> started with a synthetic `HOME`. The traceback ends with:
>
>     FileNotFoundError: [Errno 2] No such file or directory: '<the home path>'

Reproduce that crash yourself first, then fix flake8 **in the checkout** so
that an unusable home directory no longer stops it: with `HOME` pointing at a
nonexistent directory, flake8 must start normally, discover its configuration
as usual, and lint files exactly as it would with a valid `HOME`. Behaviour
with a valid `HOME` must not change. The existing project tests are the 
measure of that for you; the grader adds more checks afterwards.

## Environment

- Working tree: `/app/src` — a git checkout pinned to a single 2022 revision.
  Do **not** create commits: the tree must still be at HEAD at the end, with
  only your source change(s) as uncommitted edits.
- Run the CLI: `cd /app/src && PYTHONPATH=/app/src/src python3 -m flake8 ...`
  (this works for `--version`, for linting files, everything).
- Run tests: `cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest <path> -q`.
- The project's own unit test suite currently passes **except one pre-existing
  environment failure unrelated to this bug**:
  `tests/unit/test_pyflakes_codes.py::test_undefined_local_code` — era code
  trips a `DeprecationWarning` that this Python version turns into an error.
  Leave that test (and its file) alone. Your work must not add any other
  failure.
- `/opt` holds grader-owned reference material (including a pristine copy of
  the buggy tree). Do **not** copy, edit, or delete anything under `/opt`;
  the grader needs the pristine copy to stay pristine so it can re-run your
  reproduction against the unfixed code.

## Deliverables

Both must be true when you finish:

1. **`/app/reproduce_unknown_homedir.py`** — your own failing reproduction,
   written by you before you start fixing, demonstrating exactly the crash in
   the report above. It must be a single, self-contained Python 3 script with
   this contract:
   - run as `python3 /app/reproduce_unknown_homedir.py` while the bug is
     present: it must exit non-zero and emit the `FileNotFoundError`
     traceback;
   - run identically once the bug is fixed: it must exit 0, no traceback.
   - It must reach flake8 through the interpreter's normal module resolution
     — do not hard-code any absolute path into the `/app/src` checkout and do
     not swallow the crash in a `try/except` (the grader re-runs your script
     against an untouched copy of the buggy tree and requires it to crash
     there, and against your tree and requires it to pass).
   - Keep it focused on the crash itself (a version check or the
     configuration-discovery path is plenty). It must not exit non-zero for
     any other reason — e.g. do not assert on lint findings; the fixed tree
     must produce exit code 0.
2. **The fix, as source changes in `/app/src`** — change the program so the
   symptom above is gone. Constraints:
   - Only the source file(s) genuinely involved in this bug may differ from
     the pinned revision; every other file must stay byte-identical (the
     grader diffs the tree). No new files inside `/app/src`, no changes under
     `tests/`, no commits.
   - After your fix, all of these must hold:
     * `HOME=/nonexistent PYTHONPATH=/app/src/src python3 -m flake8 --version`
       prints the version and exits 0 (linting a file with a missing `HOME`
       works too);
     * with a valid `HOME`, linting and config behaviour are unchanged;
     * `cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest tests/unit
       -q -k "not test_undefined_local_code"` passes.

## Suggested order

1. Write `/app/reproduce_unknown_homedir.py` and watch it crash with the
   reproduction command above. The traceback and the timing of the crash
   (before any file is checked, at configuration-discovery time) tell you
   where in flake8's startup the failure lives.
2. Fix it, then re-run your reproduction and the test command above until
   both are green.

There is exactly one bug to fix: the constructor-time crash when the home
directory cannot be used. If you find yourself changing several unrelated
things, you have gone too far.