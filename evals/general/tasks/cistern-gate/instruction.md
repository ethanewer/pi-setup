# Requirement lines with invalid markers must not crash pip with a traceback

## Situation

`/app/src` is a shallow, pinned clone of the pip project
(`https://github.com/pypa/pip`), checked out at upstream commit
`9d0e2601f8c82765b0fe92001540e9a7ddd4fdf1`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
source. Python 3.12, pytest, and the packages the project's own unit-test
configuration needs are installed. There is **no network** at trial time:
everything you need is already in the image; `pip` and `git fetch` will not
work.

## The bug

A requirement line may carry an environment-marker section, for example
`pkg; python_version >= "3.12"`. That marker text must be a *valid* marker
expression. When it is not -- for instance because it contains two marker
expressions separated by a semicolon, or an unterminated string, or an
unbalanced parenthesis -- pip should treat the requirement as invalid and
report it as such.

It does not. Instead, one of pip's internal exception types from its vendored
`packaging` library (`pip._vendor.packaging.markers.InvalidMarker`) escapes the
requirement parser as a raw Python traceback. The user is told nothing about
which requirement line was at fault and the command exits without a helpful
message.

## Reproducing the failure

```
python3 /app/probe_invalid_marker.py
```

prints what happens for several requirement lines: valid lines parse, invalid
ones crash with an `InvalidMarker` exception and a `Traceback (most recent call
last)`.

A one-liner that shows the same thing:

```
python3 -c "from pip._internal.req.constructors import install_req_from_line; install_req_from_line('name; python_version == \"1\"; python_version == \"2\"')"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a requirement line
with an invalid marker section is reported as an invalid requirement -- a clean,
single error that names the offending requirement -- instead of leaking an
internal `InvalidMarker` traceback. Valid marker syntax must keep working
exactly as it does today (a marker such as `python_version >= "3.12"`, a quoted
semicolon inside a marker, and marker expressions combined with `and`/`or`
must all still parse).

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/unit/test_req.py -q -o addopts="" -p no:cacheprovider
```

The whole existing `tests/unit/test_req.py` file is green at the pinned commit;
keep it that way. Add your own tests if that helps you verify (for example
more invalid-marker shapes, or a valid marker that must not break), but the
verdict on your fix is made by the verifier, which also runs checks its own
way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch
  them.
- The verifier also asserts that the working tree remains at the pinned commit,
  that no other tracked files were modified, that no stray files were added
  inside the pip package, and that `import pip` still resolves to the checked-
  out tree at `/app/src` (it does; do not reinstall or move anything).

## What the verifier checks

1. The tree is still at commit `9d0e2601f8c82765b0fe92001540e9a7ddd4fdf1`, the
   working clone contains no other history (nothing was fetched or added),
   only the minimal tracked source file is modified, nothing was deleted, and
   `import pip` resolves to `/app/src/src/pip`.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing `tests/unit/test_req.py` still passes.
4. Hidden cases over inputs the upstream test does not use pass: invalid
   marker shapes the upstream test does not cover must raise a clean
   "Invalid requirement" error rather than `InvalidMarker`, and valid markers
   must still parse.

Deliverable: the repaired `/app/src` tree.