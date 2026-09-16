# Unpacking an overloaded call aborts the whole type check

## Situation

`/app/src` is a shallow, pinned clone of the mypy type checker
(`https://github.com/python/mypy`), checked out at upstream commit
`5bb72b788d5c031244f04f30f571f6fa199871ad` and run directly from that tree
(`python3 -m mypy` from `/app/src` imports the checked-out sources). Python
3.12 and everything the project needs to run and to test itself
(`pytest`, `pytest-xdist`, `lxml`, `typing_extensions`, `mypy_extensions`,
`pathspec`, `librt`, `ast-serialize`, ...) are installed. There is **no
network** at trial time: everything you need is already in the image; `pip`
and `git fetch` will not work.

## The bug

A small, perfectly ordinary module makes mypy abort the *entire* type-check
run with an internal error instead of reporting the real type problem. The
triggering shape is a multiple-assignment (sequence unpacking) statement whose
right-hand side is a call to an overloaded function:

```python
first: str
first, second = f(1)
```

`/app/repro.py` is such a module: `f` is an overloaded function whose
overloads return a 2-tuple `tuple[T, int]` and a homogeneous `tuple[Any, ...]`
respectively, and `g` unpacks a call result into an annotated variable of the
wrong type. What should happen is that mypy diagnoses the assignment
(`expression has type "int"`, `variable has type "str"`). What actually
happens is that the run dies at the assignment line with a message like

```
/app/repro.py:11: error: INTERNAL ERROR ...
```

and the checked module gets **no diagnostics at all** — the whole run
collapses, regardless of how the rest of the file is written.

## Reproducing the failure

```
cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py
```

While the bug is present this exits with status 2 and prints `INTERNAL ERROR`
(plus the internal stack trace of the crash). Once fixed, the same command
exits with status 1 and prints the real diagnostic:

```
/app/repro.py:11: error: Incompatible types in assignment (expression has type "int", variable has type "str")  [assignment]
```

Drive your work with the project's own test runner as well. The checker test
data lives in `test-data/unit/*.test` and the containing framework is run with
pytest, for example:

```
cd /app/src && python3 -m pytest mypy/test/testcheck.py -q -p no:cacheprovider -o addopts=""
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that multiple
assignments of this shape are diagnosed normally instead of crashing the
type-check run. The behaviour that must hold after your fix:

1. `/app/repro.py` is checked with exit status 1 and the real
   `Incompatible types in assignment (expression has type "int",
   variable has type "str")` diagnostic, and no `INTERNAL ERROR` anywhere.
2. The assignment is diagnosed when the context selects any overload whose
   declared return type cannot be the unpacking of the targets — a crash must
   never be the answer. Add your own test cases (for example in
   `test-data/unit/`) to verify the shapes you touch, but the verdict on your
   fix is made by the verifier, which also runs checks its own way.
3. The project's own type-checker test suite still passes: the code path you
   change is exercised by the tuple, unpacking and overload tests, so any
   behavioural change that is not this crash fix will show up there.

## Constraints

- Network is unavailable; everything needed is installed already; do not try
  to install anything.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, amend or add commits, or change
  build files. Do not modify anything under `test-data/` or the test
  harness (`mypy/test/`): the verifier brings its own copies of the test data
  it runs. Files under `/opt/golden`, `/tests` and `/solution` are
  harness-owned; do not touch them.
- Always run mypy with `--no-incremental --cache-dir=/tmp/mycache` from
  `/app/src`; keep the tree clean of cache artifacts.

## What the verifier checks

1. The tree is still at commit `5bb72b788d5c031244f04f30f571f6fa199871ad`,
   the working clone contains no other history (nothing was fetched or
   committed), no tracked file was deleted, only source files under `mypy/`
   are modified (at least one such modification is present), and
   `python3 -m mypy` from `/app/src` resolves to the checked-out tree.
2. The reproduction above produces the real diagnostic and no `INTERNAL
   ERROR`.
3. The project's own regression tests for this bug pass (that test data is
   kept out of the tree at `/opt/golden/` and copied in by the verifier).
4. A meaningful slice of the project's own existing checker suite still
   passes, proving the fix broke nothing else.
5. Hidden cases over unpacking shapes the upstream regression test does not
   use pass.

Deliverable: the repaired `/app/src` tree.