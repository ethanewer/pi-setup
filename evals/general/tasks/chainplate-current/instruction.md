# mypy dies with an INTERNAL ERROR on ordinary code when `global` meets `--allow-redefinition`

## Situation

`/app/src` is a shallow, pinned clone of the mypy repository
(`https://github.com/python/mypy`) at upstream commit
`1730c9535e464be8a1eee4d74f74156d75a6c0b2`, checked out in detached HEAD. mypy
is a pure-Python type checker: you run it straight from the tree with
`python3 -m mypy`, and its own test-suite runner is pytest. Everything needed
is already installed, so all work happens entirely offline. There is **no
network** at trial time: `git fetch`, `pip install` and `curl` will all fail,
so do not attempt them. Do not reset, commit to, or rewrite the history of the
clone either; the verifier checks that the tree is still at its pinned commit.

The image overlays one regression case the pinned revision does not yet
contain into the project's checked-in test data at
`/app/src/test-data/unit/check-inference.test`, exactly as the upstream fix
commit ships it. That case currently fails (see below); fixing the bug makes
it pass.

## The bug

Some completely ordinary code makes mypy abort the whole run with an INTERNAL
ERROR instead of producing a diagnostic. Create a file:

```python
x = []
def f() -> None:
    global x
    x
```

and check it from the repo root:

```
cd /app/src && python3 -m mypy --no-incremental --allow-redefinition --cache-dir=/tmp/mycache /tmp/repro.py
```

With `--allow-redefinition` enabled, the check aborts instead of completing:

```
/tmp/repro.py:4: error: INTERNAL ERROR -- Please try using mypy master on GitHub:
https://mypy.readthedocs.io/en/stable/common_issues.html#using-a-development-mypy-build
If this issue continues with mypy master, please report a bug at https://github.com/python/mypy/issues
version: 2.1.0+dev.1730c9535e464be8a1eee4d74f74156d75a6c0b2
```

and the process exits 2, so no useful diagnostics are produced at all. (If you
need a traceback, mypy prints one when you pass `--show-traceback`; the
assertion that fires is `AssertionError: Unexpectedly encountered partial
type`.)

The trigger is the combination of three things, and only the combination:

1. a module-level variable initialized to an empty list — `x = []` — so mypy
   carries it as a *partial type* until a use pins it down;
2. a function that names that variable in a `global` declaration;
3. the `--allow-redefinition` command-line flag.

Drop any one of the three (remove the `global x` line, annotate the variable,
or drop the flag) and the same file checks fine. The `global` declaration is
what triggers the crash; the internal error is reported on the line of the
function body that touches the name. It is not specific to lists: `x = {}`
or `x = set()` crash the same way, and so do multiple names in one `global`
statement.

The tree's regression case
`testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2` captures
this exact crash. Run it:

```
cd /app/src && python3 -m pytest mypy/test/testcheck.py -k testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2 -q -o addopts=""
```

It fails (the run ends `1 failed` with the assertion traceback above and the
INTERNAL ERROR recorded in the captured stderr). The sibling case
`testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine1` exercises
the same partial-type setup *without* a `global` declaration: it currently
passes and is **not** a reliable signal that the bug is fixed, because the
crash needs the `global` declaration.

Note the `-o addopts=""` in the pytest command: the project's own
`pyproject.toml` tells pytest to fan out to one worker per CPU (`-nauto`),
which is right for a CI machine and wrong inside this one-CPU container.
Clear the addopts exactly as shown whenever you run pytest here.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. the reproduction above completes normally: it must exit **1** (ordinary
   type errors) rather than 2 (internal error), report exactly the diagnostic

   ```
   /tmp/repro.py:1: error: Need type annotation for "x" (hint: "x: list[<type>] = ...")  [var-annotated]
   Found 1 error in 1 file (checked 1 source file)
   ```

   and contain no `INTERNAL ERROR` anywhere in its output;
2. the regression case
   `testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2` passes,
   and the whole data-driven checker suite (`mypy/test/testcheck.py`, roughly
   8000 cases) stays green: run

   ```
   cd /app/src && python3 -m pytest mypy/test/testcheck.py -q -o addopts=""
   ```

   which currently takes about four minutes and must end with zero failures
   after your fix;
3. all the ordinary semantics around the case keep working: a variable that
   has a real inferred or declared type must still flow through a `global`
   declaration and `--allow-redefinition` unchanged, and genuinely unannotated
   variables must still get the `Need type annotation` hint at exactly the
   place they are defined.

The tests in the tree are the spec: take them as authoritative. A one-line
behaviour change in the type checker is enough; do not weaken
`--allow-redefinition` globally, do not suppress the `Need type annotation`
diagnostic, and do not silence the crash by catching the assertion.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or add or
  rename files inside the repository, and do not touch the regression-test
  data at `test-data/unit/check-inference.test` — the verifier checks that it
  stays byte-identical to what the image overlaid.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. Tree provenance: still at the pinned commit, no upstream fix reachable,
   and the only differences from the pinned tree are the minimal source
   change that fixes the bug plus the overlaid regression-test data.
2. The CLI reproduction exits 1 with exactly the diagnostic above and no
   `INTERNAL ERROR`.
3. The project's own regression case
   `testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2` passes,
   and the project's whole `mypy/test/testcheck.py` suite
   (8000+ cases) passes end to end.
4. Hidden cases: additional programs that hit the same crash path from inputs
   the upstream regression test does not use — a `global` statement naming
   two partial-typed variables at once, a partial-typed dict with a
   subscript assignment after `global`, and a `global` declaration nested in
   an inner function — must each check normally (exit 1 with the `Need type
   annotation` diagnostics, never an INTERNAL ERROR).

Deliverable: the repaired `/app/src` tree.