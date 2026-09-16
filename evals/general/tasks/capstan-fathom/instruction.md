# flake8 crashes on syntax errors on Python 3.10+

## Situation

`/app/src` is a shallow, pinned clone of the flake8 repository
(`https://github.com/PyCQA/flake8`) at upstream commit
`d25cc10e382bcbd59cea47e0172f1e35cd3ee90d`, checked out in detached HEAD mode.
It contains exactly one commit: there is no history, no other branch, and no
other commit reachable from it. The tree is the real flake8 3.9.2-era codebase:
`/app/src/src/flake8` holds the package, `/app/src/tests` its test suite, and
`/app/src/tests/integration/test_checker.py` the integration tests for the
module that turns a failed parse into the report the tool emits.

The image runs **Python 3.12.13**. `pytest` 6.2.5 and the version era's
flake8 dependencies (`pyflakes` 2.3.1, `pycodestyle` 2.7.0, `mccabe` 0.6.1)
are installed. The project is **not** pip-installed; import it straight from
the checkout:

```
export PYTHONPATH=/app/src/src
```

There is **no network** at trial time: `git fetch`, `pip install`, `curl` and
any other network use will fail.

## The bug

Since Python 3.10, when flake8 checks a Python file that fails to parse, it
crashes instead of doing its job:

```
AttributeError: 'int' object has no attribute 'rstrip'
```

The file being checked is perfectly normal — it is exactly the kind of file
the tool must be able to report on. Users on Python 3.10 and newer get this
traceback instead of the tool's usual syntax-error report (the `E999` result
that names the offending line and column), so every file with a syntax error
in a whole project is uncheckable.

The root cause is a data-shape assumption that stopped being true on
Python 3.10. When the parser fails it attaches information to the
`SyntaxError` describing where the error is. That record used to be a
4-element tuple; on Python 3.10 and newer the parser appends extra trailing
fields describing the *end* of the offending section. The code that turns a
`SyntaxError` into a report position blindly uses the tuple's last element,
which is now an integer end-offset instead of the offending source text, and
then calls string methods on it.

A regression test for this behaviour is already in the tree — upstream added
it to `/app/src/tests/integration/test_checker.py` when they fixed the bug,
and this checkout is the state from just before that fix, with the corrected
test file in place. Run it:

```
cd /app/src
PYTHONPATH=/app/src/src python3 -m pytest \
  tests/integration/test_checker.py \
  -k test_handling_syntaxerrors_across_pythons \
  -q -W ignore::DeprecationWarning -p no:cacheprovider
```

It fails with the traceback above. That failure **is** the bug.

A note on scope: the `flake8` command line itself cannot start in this image —
`flake8 --version` dies with an unrelated `AttributeError: 'EntryPoints'
object has no attribute 'get'`, because this era's plugin-discovery code calls
an `importlib.metadata` API that Python 3.10+ no longer provides. That is a
separate, known, pre-existing incompatibility of this old release with a
modern interpreter; it is **not** the bug you are asked to fix, it cannot be
fixed as part of this task, and the verifier never invokes the command line.
Everything that matters — the parser hook, the checker machinery, the
report-position recovery — is reachable through `import flake8.checker` and
through the test suite, so drive your work with the tests.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. The regression test above passes (`1 passed`).
2. No `AttributeError` is raised on a file that fails to parse: the code that
   recovers the report position returns the position the exception actually
   describes, for every shape the exception can take.
3. Everything that already works keeps working. In particular, the pre-3.10
   four-element tuple layout must keep producing exactly the same positions
   it always did, and the suite listed below stays fully green.

The tests in the tree are the spec — treat them as authoritative. If you want
to see what the parser actually attaches on this interpreter, construct a
syntax error and inspect it:

```
python3 - <<'PY'
try:
    compile("x = 1\nif True print(1)\n", "<snippet>", "exec")
except SyntaxError as e:
    print(e.args)
PY
```

## Constraints

- Network is unavailable; everything needed is installed and present.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, do not fetch, do not add remotes or
  commits, do not add or rename files inside the repository, and do not change
  anything under `/app/src/tests` — in particular
  `tests/integration/test_checker.py` must stay byte-for-byte identical to the
  upstream regression test it came from (the verifier checks that).
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.
- Do not attempt to fix the unrelated command-line plugin-discovery crash
  described above.

## Verifying your fix

After each change to the source, re-run the tests. The full check the
verifier runs is:

```
cd /app/src
PYTHONPATH=/app/src/src python3 -m pytest \
  tests/integration/test_checker.py \
  tests/unit/test_checker_manager.py tests/unit/test_file_checker.py \
  tests/unit/test_statistics.py tests/unit/test_utils.py \
  tests/unit/test_violation.py \
  -q -W ignore::DeprecationWarning -p no:cacheprovider
```

A correct fix leaves every one of these 135 tests passing.

## What the verifier checks

1. Tree provenance: the checkout is still at the pinned commit; the upstream
   fix commit is not reachable from it; the working tree differs from the
   commit only in the minimal source fix and the shipped regression-test file;
   and `tests/integration/test_checker.py` is byte-identical to
   `/opt/golden/test_checker.py`.
2. The regression test above passes against your repaired tree, and the
   project's own suite listed above passes in full (135 tests).
3. Hidden cases: further `SyntaxError` inputs the upstream test does not use
   — real parse failures of multi-line modules, errors whose source text is
   unavailable, errors where the appended end-fields point somewhere other
   than the start position, the legacy pre-3.10 tuple layout, and the related
   tokenisation-error path — must all yield the exact position the exception
   carries, with no crash.

Deliverable: the repaired `/app/src` tree.