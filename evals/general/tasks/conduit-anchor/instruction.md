# conduit-anchor

You are working inside the real upstream `pytest-dev/pytest` repository,
checked out at a pinned commit in `/app/src` (the working tree starts
clean). There is a bug in this tree's approximate-comparison machinery.
Your job is to find it, fix it in the working tree, and prove the fix with
the project's own test tooling. You are deliberately **not** told which
file or function to change: localising the bug is part of the task.

## Environment

- Python 3.12 with the project's own `dev` test dependencies installed
  (argcomplete, attrs, hypothesis, mock, requests, setuptools, xmlschema).
- The checkout at `/app/src` is installed **editable**, so any edit you make
  under `/app/src/src` is live in the next `import pytest`/`pytest` run.
- **There is no network** in this container. Everything is already baked in;
  do not attempt `pip install`, `git fetch`, or any download.
- `cpus = 1`: one vCPU. pytest is pure Python here, so the whole
  `testing/python/` suite takes only a few seconds — there is no excuse to
  skip running it.
- The tree at `/app/src` is shallow (one commit) and detached; do not
  commit, fetch, or otherwise modify `.git`, and do not change `HEAD`.

## The bug (user-visible symptom)

`pytest.approx()` supports datetime/timedelta comparisons when the tolerance
is given as an explicit `timedelta`, e.g.
`pytest.approx(dt, abs=timedelta(seconds=1))`. Timedelta values also support
an **absolute** tolerance the same way:

```python
>>> from datetime import timedelta
>>> timedelta(seconds=100) == pytest.approx(timedelta(seconds=100), abs=timedelta(seconds=1))
True
```

For **every other value type**, `approx` also accepts a **relative**
tolerance given as a plain number — a fraction of the expected value, e.g.
`rel=0.01` for "within 1%". For timedelta comparisons that is broken:
passing a plain number as `rel` fails immediately with an error even though
the same plain number works for floats, ints and decimals:

```python
>>> timedelta(seconds=100) == pytest.approx(timedelta(seconds=100.5), rel=0.01)
Traceback (most recent call last):
TypeError: relative tolerance for timedelta must be a timedelta, got float
```

`timedelta(seconds=109) == pytest.approx(timedelta(seconds=100), rel=0.1)`
(10% of 100s = 10s, and 109 is 9s away) must be `True`, and
`timedelta(seconds=111) != pytest.approx(timedelta(seconds=100), rel=0.1)`
(11s away) must be `True` as well. The same failure occurs when timedelta /
datetime scalars appear **inside** a sequence or mapping:

```python
>>> [timedelta(seconds=105)] == pytest.approx([timedelta(seconds=100)], rel=0.05)
TypeError: relative tolerance for timedelta must be a timedelta, got float
```

Invalid tolerances are also not rejected cleanly: a **negative** relative
tolerance, a **NaN** relative tolerance, and a **negative timedelta**
absolute tolerance must each raise `ValueError` with a clear message, the
same way the plain-number comparison machinery already rejects them.

The expected behaviour after your fix:

- `rel` for timedelta comparisons is a **plain number** (int/float); the
  effective tolerance is `rel * abs(expected)` as a `timedelta`.
  `timedelta(seconds=109) == approx(timedelta(seconds=100), rel=0.1)` is
  `True`; `timedelta(seconds=111) != approx(timedelta(seconds=100), rel=0.1)`
  is `True`; the tolerance scales with the magnitude of the expected value.
- when both are given, the effective tolerance is
  `max(abs(timedelta), rel * abs(expected))`.
- `rel` given as a `timedelta` is no longer accepted (it must be a number).
- negative rel, NaN rel and negative timedelta abs raise `ValueError` with
  messages matching the plain-number validation
  ("relative tolerance can't be negative", "relative tolerance can't be
  NaN", "absolute tolerance can't be negative").
- datetime/timedelta scalars inside sequences and mappings compare
  correctly, routing through the timedelta comparison class.

## Requirements

1. Fix the tree so the behaviour above holds, for direct timedelta values,
   and for timedelta/datetime scalar elements inside sequences and
   mappings. Everything else must keep working exactly as before: the rest
   of the project's own `testing/python/` test suite must stay green.
2. The graded tree must be byte-identical to the original except for **the
   single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; do not edit any test file — the grader
   overlays the project's own updated regression tests for this bug itself.
   If you create scratch files to investigate, delete them before you
   finish; make no commits. The grader compares every file's bytes against
   the pinned commit's own blobs, so cosmetic side-changes also fail.
3. The file at `/opt/golden/approx.py` is the project's **own regression
   test file for this bug** (the version that landed together with the fix,
   which this tree predates). You may read it to learn the exact expected
   behaviour, and you may copy it over `testing/python/approx.py` in a
   scratch copy of the tree to reproduce and verify — but remember that the
   graded tree must NOT contain that overwrite (the grader does it itself).
   Note the in-tree copy of `testing/python/approx.py` still encodes the
   old behaviour and its timedelta-`rel` tests contradict the fixed
   behaviour; that is expected and is why the grader uses the golden file.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

Also available at `/app/repro_symptom.py`: a self-contained reproduction
script (exits 0 once the bug is fixed; run it with `python3`).

## Working loop (recommended)

1. **Reproduce.** Run `python3 /app/repro_symptom.py` — it raises the
   `TypeError` on this tree. (You can also run the golden regression file
   against a scratch copy of the tree, or write your own scratch repro and
   delete it afterwards.)
2. **Localise.** `pytest.approx` is implemented under
   `/app/src/src/_pytest/`; the timedelta comparison class is in the same
   module as the plain-number one whose validation messages yours must
   match. Reading how the plain-number class validates and combines `rel`
   and `abs` (and how sequence/mapping elements are routed to the per-type
   comparison classes) will find the spot.
3. **Fix.** Apply a minimal change.
4. **Verify.** After your fix: `python3 /app/repro_symptom.py` exits 0; the
   golden regression file passes when overlaid in a scratch copy; and
   `cd /app/src && python3 -m pytest testing/python/ -q -p no:cacheprovider`
   stays green (it is green on the untouched tree — take a baseline first).
5. Delete any scratch files and undo any modifications outside the one
   source file, then write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- overlay the project's own regression tests for this bug (baked into the
  image at `/opt/golden/approx.py`) over the in-tree test file, then run
  them together with the project's own `testing/python/` suite; every test
  must pass, including regression variants the upstream tests do not use:
  microsecond-resolution and negative expected values, validation of
  negative/NaN tolerances, and tuple/multi-entry-mapping routing.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.