# Fix a mypy false positive: unreachable code that is reachable

## Environment

`/app/src` is a full checkout of the **mypy** type checker (the real
`python/mypy` source tree) at a pinned upstream commit. Its runtime
dependencies and the project's own test runner are preinstalled system-wide.
There is **no network** in this container. mypy is not pip-installed: run it
from the checkout, e.g.

```sh
cd /app/src && python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/mycache somefile.py
```

so that the checked-out sources — including any change you make to them — are
what gets executed.

Read `/app/README.md` for the environment guide. Do not modify anything
outside `/app/src`.

## The bug report

A user reports that mypy diagnoses reachable code as unreachable:

> I wrote a small loop that counts how many times each element of a list
> occurs. The counters live in an ordinary dictionary, and a brand-new key
> starts at zero:

> ```python
> if key not in counts:
>     counts[key] = 0
> counts[key] += 1
> ```

> The first time a key is seen the `if` branch must run — a fresh dictionary
> starts empty — so the statement `counts[key] = 0` is definitely reachable.
> Yet when the dictionary keys are members of an enum, mypy with
> `--warn-unreachable` claims `counts[key] = 0` is a `Statement is
> unreachable` error. The same loop with the same dictionary works fine when
> the keys are strings or integers.

Further findings from the reporter:

- The loop must be type-annotated (`list[SomeEnum]`, `dict[SomeEnum, int]`);
  with unannotated variables the symptom does not appear.
- The enumeration in the report defines **exactly one member** (e.g.
  `RED = 1`). Adding a second member to the enum makes the spurious warning
  disappear, even though the code is identical.
- The same condition restructured, for example stored in a helper variable
  before the `if`, does not trigger the warning — the code is semantically
  identical, so the verdict depends on how the condition is written, not on
  what it means.
- The warning only appears with `--warn-unreachable`; without it mypy stays
  silent.

Your job: make mypy stop emitting this false positive, for the reported
program and for every reasonable variation of it.

## Deliverables

1. `/app/repro.py` — your own minimal reproduction, written by you, in the
   spirit of the report above: a single self-contained Python source file
   that, type-checked by the tree's mypy at the current (broken) state,
   produces the false positive. The verifier will run exactly this command
   from `/app/src`:

   ```
   python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/<fresh> /app/repro.py
   ```

   Against the current tree that command must fail with exit code 1 and must
   emit a `Statement is unreachable` error on a statement that is really
   reachable. Against the repaired tree (your fix) the same command must
   report `Success: no issues found` and exit 0.

   `repro.py` must not read arguments, environment variables, or anything
   else: the reproducible behaviour must live in the file itself.

2. Fix the bug in the tree at `/app/src`. The false positive must be gone for
   the reported pattern and generalise to other container membership checks
   of the same kind, and the fix must stay sound: code that legitimately
   relies on well-established narrowing behaviour must continue to
   type-check. The fix must be a source-level change to the type checker's
   own code — editing or deleting test data is not a fix. Keep the tracked
   working tree clean apart from your purposeful source change (no stray new
   files inside `/app/src`).

## Recommended self-checks before you finish

1. The reproduction command above passes on the repaired tree.
2. The project's own narrowing regression tests stay green — this is the
   area of the codebase your change affects, and it includes cases that
   assert valid narrowing is preserved:

   ```sh
   cd /app/src && python3 -m pytest mypy/test/testcheck.py -k 'Narrowing or Narrow' -q
   ```

   (Do not run the whole mypy suite; it takes tens of minutes on one CPU.)

## How the result is judged

- `/app/repro.py` must exist, must fail with the false positive against the
  pre-fix state of this tree, and must pass after your fix.
- The repair must actually be in the tree: the verifier re-checks the working
  tree byte-for-byte against the pinned commit and requires that every file
  other than the one source file the bug lives in is untouched and that no
  new files were added inside the git tree.
- The verifier runs the upstream project's own regression test for this bug
  and requires it to pass, runs the narrowing test subset above, and runs
  additional input variations exercising the same code path.
- The checkout holds only the pinned commit and cannot fetch anything: there
  is no later history to consult, so you must derive the fix from the code as
  it is.