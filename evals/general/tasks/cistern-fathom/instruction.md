# Fix the `.get(type=...)` crash in the werkzeug checkout

A real upstream checkout of the **Werkzeug** web framework lives at
`/app/src`. It is faithful to the upstream project at a known historical
state — complete with a genuine bug that upstream later fixed. Your job is to
find the bug, understand it, and repair the library so the behavior described
below holds.

## The user-visible symptom

`request.args`, `request.form` and `request.files` — the parsed query string
and form data of any WSGI request built with Werkzeug — are implemented on top
of a family of dictionary classes whose `.get()` method converts stored
values on the way out:

```python
request.args.get("page", default=1, type=int)
```

The documented contract of `.get(key, default=None, type=None)` on those
classes is:

- if `key` is absent, return `default`;
- if the stored value can be converted by the `type` callable, return the
  converted value;
- if the stored value **cannot** be converted, return `default` — that is
  exactly what the default argument is for.

Users hit this bug in ordinary request handling the moment a stored value has
a type the converter rejects (for example the empty field `flag` parsed as
`None`, which `int()` refuses):

```python
>>> from werkzeug.datastructures import TypeConversionDict
>>> TypeConversionDict(baz=None).get("baz", default=-1, type=int)
Traceback (most recent call last):
  ...
TypeError: int() argument must be a string, a bytes-like object or a real
number, not 'NoneType'
```

The call should have returned `-1`. Instead, an exception that this `.get()`
API is supposed to absorb escapes into request-handling code and crashes it.
`None` for `int()` or `float()`, a list or dict for `int()`, and every other
"the converter rejects this input" case are precisely the cases the default
argument exists for.

## Deliverable

Repair the checkout at `/app/src` so `.get(key, default=..., type=...)`
implements its documented contract:

1. an absent key returns the default;
2. a convertible value returns the converted value (`"2"` with `type=int`
   returns `2`);
3. a value the converter cannot convert returns the default — `None` for
   `int()` or `float()`, a list or dict for `int()`, anything else the
   converter refuses;
4. exceptions a custom converter raises for reasons other than "cannot
   convert" (e.g. a `KeyError` or `ZeroDivisionError` inside the converter
   callable) must still propagate to the caller unhandled.

The delivered artifact is the repaired source tree itself: `/app/src` with
your fix in it. There is no report file to write and nothing to install — the
image already imports this checkout as the `werkzeug` package (editable
install), so your edits take effect immediately.

## Constraints

- The tree is graded for *provenance*. Outside the minimal library change
  your fix requires, every tracked file under `/app/src` must remain
  byte-identical to the checked-out revision: do not edit any other file, and
  do not add files inside the repository tree — put scratch files under
  `/tmp` instead.
- Leave the repository at its checked-out revision (`HEAD` must stay where it
  is). Do not re-clone, fetch, or check out any other revision.
- There is no network at trial time. Everything you need is already in the
  image.

## Environment

- The checkout is at `/app/src` (a git repository, detached at the historical
  revision that still has the bug).
- `werkzeug` is importable from anywhere, resolving to the source tree, e.g.:

  ```python
  python3 - <<'PY'
  from werkzeug.datastructures import TypeConversionDict
  print(TypeConversionDict(baz=None).get("baz", default=-1, type=int))
  PY
  ```

  Today this crashes with `TypeError` instead of printing `-1`.
- The project's own unit tests are at `/app/src/tests`, runnable with the
  installed `pytest`:

  ```bash
  cd /app/src && python3 -m pytest -q tests/test_datastructures.py
  ```

  The class most relevant to this bug is `TestTypeConversionDict` in
  `tests/test_datastructures.py`; read it to see what the suite already locks
  in about `.get()` conversion semantics.
- The environment already has the packages the project's `tests/conftest.py`
  imports (`pytest`, `xprocess`, `ephemeral_port_reserve`), so the project's
  own test runner works normally.

Your repair is complete when the repro above prints `-1` and the project's own
test module passes.