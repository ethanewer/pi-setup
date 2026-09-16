# @pytest.mark.parametrize with a comma-terminated argument name

## Situation

`/app/src` is a shallow, pinned clone of the pytest project
(`https://github.com/pytest-dev/pytest`), checked out at an upstream commit,
and installed from that tree in editable (development) mode, so the code you
import is exactly the checked-out Python source under `/app/src/src`. Python
3.12 and pytest (plus the development extras the project's own test suite
needs) are installed. There is **no network** at trial time: everything you
need is already in the image; `pip` and `git fetch` will not work.

## The bug

`@pytest.mark.parametrize` accepts argument names either as a tuple, e.g.
`("arg",)`, or as a comma-separated string, e.g. `"arg"` or `"arg1, arg2"`.
When a single argument name is written as a *comma-terminated* string --
`"arg,"` -- users expect it to behave exactly like the equivalent tuple form
`("arg",)`:

```python
import pytest

@pytest.mark.parametrize("arg,", [("a",), ("b",)])
def test_example(arg):
    assert arg in ("a", "b")   # one-element tuples are unpacked
```

That is how the tuple form works: the argvalues list holds **one-element
tuples** and each test invocation receives the single element (`"a"`, then
`"b"`). In this checkout the comma-terminated string form does not unpack
those tuples: each invocation receives the whole one-element tuple, so the
test above fails with something like `assert isinstance(('a',), str)` or, for
the membership check, `assert ('b',) in ('a', 'b')`.

The string form **without** a trailing comma (`"arg"`) must keep its
documented behaviour *of passing each argvalue through as-is* (so with a list
of one-element tuples the test receives the tuples), and the tuple form
`("arg",)` must keep unpacking. Only the comma-terminated single-name form is
wrong.

## Reproducing the failure

A probe test file lives at `/app/test_parametrize_comma.py`. Run it with the
project's own test runner from the checkout:

```
cd /app/src && python3 -m pytest /app/test_parametrize_comma.py -q -p no:cacheprovider
```

The first test currently fails: `assert isinstance(('a',), str)`. After your
fix both tests must pass, and the first must receive the string element, not
the tuple.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a comma-terminated
single-argument string behaves exactly like the tuple form: each item of the
argvalues list is unpacked and the test receives its single element. The forms
that already work must be left alone:

- `"arg"` (no comma) still passes each argvalue through as-is (tuples stay
  whole);
- `("arg",)` still unpacks one-element tuples;
- multi-name strings (`"left, right"`) still unpack each tuple.

Drive your work with the project's own test runner from `/app/src`:

```
cd /app/src && python3 -m pytest testing/python/metafunc.py -q -p no:cacheprovider
```

The whole parametrize test module is green at the pinned commit; keep it that
way. Add your own tests where that helps you verify, but the verdict on your
fix is made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the tree descends from the pinned upstream
  commit, that only the minimal tracked source file was modified, and that no
  new files were added inside `src/` or `testing/`.

## What the verifier checks

1. The tree is still at (or directly on top of) the pinned upstream commit,
   no extra tracked files were changed, and the repair touches only the
   minimal source surface.
2. The probe at `/app/test_parametrize_comma.py` passes (the bug is gone).
3. The project's own existing parametrize test module,
   `testing/python/metafunc.py`, still passes.
4. The project's upstream regression tests for this behaviour pass.
5. Hidden cases over inputs the upstream tests do not use pass, including
   whitespace variants of the comma-terminated form with non-string values, a
   guard that the no-comma forms keep their semantics, and the indirect/ids
   forms of the same parametrize path.

Deliverable: the repaired `/app/src` tree.