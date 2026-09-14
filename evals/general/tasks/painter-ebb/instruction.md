# A false error from every factory that builds through a `Type[T]` parameter

`/app/src` is a real, unmodified working copy of **mypy**, the static type
checker for Python, as it was right before one behavioral bug was fixed. The
tree is a bare detached checkout (single commit frozen at the buggy revision,
**no git history, no network**) and it is fully wired up: Python 3.12.13, the
project's runtime dependencies (`typing_extensions`, `mypy_extensions`,
`pathspec`, `librt`, `ast-serialize`) and its test dependencies (`pytest`,
`pytest-xdist`, `lxml`) are installed, and the sources run directly from
`/app/src` (`python3 -m mypy`). A read-only pristine copy of this same tree
lives under `/opt/pristine-src`. You must localise the defect in the real tree
from the symptom alone, repair it, and prove the repair with mypy's own tools.

## The failing behaviour

Factory functions that receive a *type object* through a parameter annotated
`Type[T]`, where the type variable `T` is bounded by a union of classes, are
rejected by mypy with spurious errors. Concretely: a helper such as

    from typing import Type, TypeVar, Union
    T = TypeVar("T", bound=Union[SomeClassA, SomeClassB])
    def make(ftype: Type[T], ...) -> T: ...

that builds an instance by calling the type object — `ftype()` or
`ftype(argument)` — and returns it is reported erroneous on every such
constructor call. The message is `Incompatible return value type (got
"SomeClassA | SomeClassB", expected "T")` at the return statement, **even
though** mypy itself infers the constructed value precisely: a
`reveal_type(ftype(...))` shows the individual class that was passed in, not
the union. Both the no-argument call form and the one-argument call form are
affected. The code is valid Python and the classes are ordinary instantiable
classes with compatible constructors; a real mypy release accepts it.

## What to do

1. **Write your own failing reproduction first.** Create `/app/repro.py` — a
   small standalone Python file that demonstrates the bug: a type variable
   bounded by a union of two or more classes whose instances are created by
   calling a `Type[T]` parameter (try both the no-argument and the
   argument-taking forms; `reveal_type` lines are fine). Running
   `python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py`
   from `/app/src` must currently fail with the error described above (exit
   status 1, `Incompatible return value type`). Keep iterating on this file
   until it exposes exactly that behavior. This reproduction is a deliverable;
   the verifier runs it against both the pristine and the repaired trees.
2. **Localise the defect.** The type checker *does* compute the precise
   constructed type; the wrongness is in how a `Type[T]` callee's return type
   is prepared while type-checking a call. Read the expression-checking code,
   especially where a type object is turned into a callable and where the
   result of that conversion is adapted to a type-variable context, and
   experiment with the reproducer and small variants (different unions,
   keyword arguments, nested unions, factories defined as methods).
3. **Fix it** so that calling a type object through a `Type[T]` parameter whose
   bound is a union type-checks correctly in every branch: the checker must
   treat each possible constructor as returning the type variable instance,
   not the union of classes. Do not special-case particular class names, do
   not silence errors globally, do not rewrite the checked files and do not
   weaken the type system — repair the substitution in the checker itself.
4. **Prove the fix** with the project's own machinery, from `/app/src`:

   ```bash
   python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py   # must now exit 0
   python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro2.py  # try a couple of variants
   PYTHONPATH=/app/src python3 -m pytest mypy/test/testcheck.py -q -k 'testTypeUsingTypeC' \
       -p no:cacheprovider                                # must stay fully green
   ```

   The `testTypeUsingTypeC*` cases are the project's own tests for exactly
   this machinery (`Type[T]` calls, construction through type variables and
   unions); they pass at the buggy revision too, so they are a regression
   check that your change broke nothing, not a hint at the fix.

5. **Write `/app/diagnosis.md`** — a short root-cause note (several sentences)
   stating, in your own words: **where** the defect lives (which module of
   mypy), **what** the code did wrong when preparing the constructor callee
   for a union-bounded type variable, and **the minimal fix** you applied.

## Deliverables (all checked)

1. `/app/repro.py` — your own reproduction of the bug as described above.
2. `/app/diagnosis.md` — the root-cause note described above.
3. The repaired source tree in `/app/src` (ordinary file edits in place).

The verifier will run your reproduction and additional hidden files against
the pristine tree (where the bug must still reproduce) and against your
repaired tree (where they must all type-check cleanly), then overlay the
project's own regression tests and run them with the project's own pytest
suite against your repaired tree.

## Constraints

- No network: the trial runs fully offline; everything you need is already in
  the image. Do not try to fetch or install anything.
- Do not modify the tree's test files: the `test-data/unit/*.test` data files
  and the `mypy/test/` runner modules are compared against their pristine
  content, and the verifier replaces the three check-classes/check-python310/
  check-python312 data files with pristine copies of its own before running
  the suite, so editing them to force a pass is detected and scored as a
  failure.
- Do not delete or regenerate `/app/src`; repair it in place, and leave every
  file that is not part of the fix untouched.

The expensive part is finding the defect, not running the checks — a single
mypy run takes about three seconds and each pytest invocation about two. If
the reproduction works, you are on the right track; if you find yourself
special-casing inputs, step back and find the real substitution bug.