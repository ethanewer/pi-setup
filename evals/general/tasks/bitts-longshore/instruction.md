# bitts-longshore

You are working inside a real open-source codebase: **SymPy**, the symbolic
mathematics library, checked out at a pinned historical commit in
`/app/src` (the working tree starts clean and the project is already
importable). There is a bug in this tree's handling of **modulo arithmetic
with symbols that carry an integer assumption**. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- Python 3.12 at `/usr/local/bin/python`; the tree is installed in editable
  mode (`pip install -e .`), so `import sympy` works from anywhere, the
  package's modules are loaded straight out of `/app/src`, and edits you
  make there take effect immediately.
- `pytest 9.1.1` and `hypothesis 6.168.0` are installed. The project's own
  test configuration lives at the repo root in `pyproject.toml`, so run
  pytest from the repo root:
  `cd /app/src && python -m pytest <path> -p no:cacheprovider`.
  Keep runs targeted — the **full suite is impractical on this machine**, so
  run individual test files or individual test nodes (e.g.
  `python -m pytest sympy/core/tests/test_something.py::test_something`),
  not the whole `sympy/` tree.
- **`cpus = 1`**: one vCPU; pytest on sympy is mostly single-threaded, but
  keep coverage targeted anyway.
- Treat the container as **self-contained**: everything you need is already
  in the image. Do not plan around fetching anything.

## The bug (user-visible symptom)

A user reports the following. Symbolic modulo expressions change value when a
symbol is declared integer — even though an assumption is supposed to only
*add* simplifications, never alter the arithmetic:

- `Mod(2*Mod(x, 3), 5)` with a plain symbol `x` evaluates to
  `Mod(2*Mod(x, 3), 5)`, but with `x` declared `integer=True` the
  expression simplifies to something different: the **inner remainder ends
  up multiplied by itself** (squared), so
  `Mod(2*Mod(x_int, 3), 5).xreplace({x_int: x})` is **not equal** to the
  plain-symbol form, even though they describe the same value.
- The same discrepancy appears in another family built with `floor`,
  e.g. `8*Mod(floor(x/64), 4)`: declaring the symbol integer changes the
  expression again.

So the contract you must restore is: **for any modulo expression, the form
computed with an integer-assumed symbol must simplify to the same expression
as the form computed with the equivalent plain symbol** (after substituting
the assumed symbol back). The two forms must always be equal.

Reproduce the failure against the provided tree **before** you change
anything, then make the smallest possible change that fixes the mechanism —
not just one input. (Your reproduction will be re-run against a pre-fix copy
of the tree during grading.)

## Your job

1. **Write a failing reproduction first.** Before touching any source code,
   write **`/app/repro.sh`** — your own minimal reproduction of the symptom
   above. Its contract:

   - It takes **one optional positional argument, the repository directory
     to test** (`/app/repro.sh [REPO_DIR]`), defaulting to `/app/src`.
   - Inside that repository it creates a **temporary pytest test file**,
     placed in the test directory of the package that owns the affected
     behaviour and named following the project's own test-file convention
     (`test_*.py`). The test captures the contract above (the 
     integer-assumed form must equal the plain form, in both reported
     families or equivalent arithmetic), in a form that **fails on the
     unfixed code**.
   - It runs the project's own test runner — `python -m pytest <that file>`
     — from the repository root, and prints everything the runner prints
     (stdout and stderr) and nothing else.
   - It removes the temporary test file again before exiting (a `trap` on
     `EXIT` is the clean way), leaving the repository it was pointed at
     exactly as it found it.
   - It must not depend on the caller's current directory, and must not
     touch anything outside the repository directory it was given plus
     `/tmp`.
   - It exits **0 if and only if the temporary test passed** (the symptom is
     absent) and **non-zero** otherwise (the symptom is present, and the
     printed runner output shows the failure).

   Confirm, on the unfixed tree, that it exits non-zero before you change
   anything. The grader will also run it against a **pre-fix copy** of the
   tree (it must fail there again) and against your **repaired** tree (it
   must pass).

2. **Fix the tree.** Make the smallest possible change to `/app/src` so that
   `/app/repro.sh /app/src` exits 0. Fix the mechanism, not just one input:
   the defect is reachable with any inner/outer moduli and coefficients, and
   with the `floor` family as well (see Grading). Do not wrap the test
   runner, do not special-case your reproduction, and do not weaken the
   behaviour of unaffected modulo expressions.

3. **Break nothing else.** Run the project's own existing tests for the
   module that owns the affected behaviour (the arithmetic tests that cover
   `Mod`) and confirm they still all pass with your fix in place.

4. **Explain the change.** Write **`/app/summary.md`** (non-empty): the
   symptom in your own words, the root cause you found, the change you made,
   and the tests you ran.

## Constraints on the graded tree

- **Byte-exactness.** The verifier compares every file inside `/app/src`
  byte-for-byte against the pinned commit's own blobs. The working tree may
  differ from the pinned commit in **exactly one source file: the file the
  bug lives in** (the file you had to fix). Every other tracked file must be
  byte-identical, and **no new files** may appear anywhere inside
  `/app/src` (your two deliverables live outside it, in `/app`). Do not
  delete, rename or reformat anything; delete any scratch files you create
  while investigating before you finish; make **no commits**.
- Do not modify the project's test files. Do not add, delete or edit
  anything under `.git` (no fetch, no graft, no rewriting history): the
  grader requires `HEAD` to still be the pinned commit and the upstream fix
  commit to remain unreachable from this clone.

## Deliverables

- `/app/src` — the fixed working tree
- `/app/repro.sh` — executable, your own reproduction (contract above)
- `/app/summary.md` — the explanation

## Grading

The grader (1) re-runs your `/app/repro.sh` against the repaired tree (must
exit 0) and against a pre-fix copy of the tree (must exit non-zero);
(2) runs the project's own regression test for this bug, extracted from the
fixed upstream history, against both trees; (3) runs the project's existing
arithmetic test module with that regression test planted, which must pass in
full; (4) runs hidden cases that reach the same code path from inputs the
upstream test does not use (other moduli and coefficients, an even-assumption
trigger, merged multiplier factors) — each must pass on your repaired tree
and fail on the pre-fix copy. A correct fix passes every one of these; any
shortcut you can think of is exactly what the grader also checks for.