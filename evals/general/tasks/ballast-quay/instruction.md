# Implicit string concatenation of a raw and a non-raw literal is wrongly flagged

## Situation

`/app/src` is a shallow, pinned clone of the `pylint` repository from
`https://github.com/pylint-dev/pylint` (development version 4.1.0-dev0),
checked out at upstream commit `2ef1766c3923ee7753cea771959227a35e74972c` and
installed from that tree in editable (development) mode, so the `pylint`
package you import is exactly the checked-out source. Python 3.12, `pytest`,
and the project's own test dependencies are installed. There is **no network**
at trial time: everything you need is already in the image; `pip` and
`git fetch` will not work.

## The bug

pylint's `implicit-str-concat` check (message `W1404`) is meant to catch a
forgotten comma between string literals. An expression like
`fruits = ["apple" "banana"]` was almost certainly meant to be
`fruits = ["apple", "banana"]`, so pylint flags the juxtaposition.

But one kind of implicit concatenation can never be a mistake: a **raw**
string literal (`r"..."`) juxtaposed with a **non-raw** one. The two kinds of
literal cannot be merged into a single string anyway, so such a juxtaposition
is necessarily deliberate concatenation, not a forgotten comma. The check
nevertheless reports `W1404` whenever the two adjacent literals differ in
whether they are raw, in any context.

## Reproducing the failure

```
cat > /tmp/repro.py <<'EOF'
MIXED_RAW1 = [r"\d" "\n"]
MIXED_RAW2 = "\n" r"\d"
print(MIXED_RAW1, MIXED_RAW2)
EOF
python3 -m pylint /tmp/repro.py --disable=all --enable=implicit-str-concat --score=n
```

While the bug is present this prints

```
/tmp/repro.py:1:0: W1404: Implicit string concatenation found in list (implicit-str-concat)
/tmp/repro.py:2:0: W1404: Implicit string concatenation found in assignment (implicit-str-concat)
```

and exits with status 4 (messages were emitted). A ready-made probe,
`/app/probe.py`, runs pylint over several mixed raw/non-raw shapes plus a
plain-concatenation control and exits nonzero while the bug is present.

## What you need to do

Fix the checked-out tree at `/app/src` so that adjacent string literals that
differ in rawness no longer trigger `implicit-str-concat` — in a list, tuple,
set, dict, call, assignment, or any other context — while every other
behaviour of the check is preserved:

- a raw/raw or plain/plain juxtaposition must still be reported wherever it
  was before, including inside a list or tuple (that is the forgotten-comma
  case; both literals could have been written as a single literal);
- only the literals themselves must decide: the prefix spelling used (`r`,
  `R`, `u`, none) must not matter, and a juxtaposition of a raw literal with
  an un-prefixed or `u`-prefixed one must be silent.

Drive your work with the project's own test runner from `/app/src`. Two
existing tests are relevant; the functional one is currently failing at the
pinned commit because of the false positive, and making it green again is part
of the fix:

```
cd /app/src
python3 -m pytest tests/test_functional.py -k implicit_str_concat -q -p no:cacheprovider
python3 -m pytest tests/checkers/unittest_strings.py -q -p no:cacheprovider
```

Add your own tests if that helps you verify, but the verdict on your fix is
made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything you need is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier checks that the working tree is still at the pinned commit,
  that no history was fetched or added, that no tracked file was deleted,
  that the only modified tracked files are linter source files under
  `pylint/` (at least one such modification present — fixing a linter bug
  means modifying linter source, not test files or configuration), and that
  `import pylint` still resolves to the checked-out tree at `/app/src` (it
  does; do not reinstall or move anything).

## What the verifier checks

1. The tree is still at commit `2ef1766c3923ee7753cea771959227a35e74972c`,
   the working clone contains no other history (nothing was fetched or
   added), no tracked file was deleted, only tracked source files under
   `pylint/` are modified (at least one), and `import pylint` resolves to
   `/app/src/pylint/__init__.py`.
2. The project's own upstream regression test for this behaviour passes. That
   test is the fix-commit version of the `implicit_str_concat` functional
   test, kept out of the tree at `/opt/golden/` and copied in by the verifier
   (which then also re-runs your tree's own version of that test).
3. The project's own unit tests for the string checker still pass.
4. Hidden cases over raw-prefix shapes, plain-concatenation guards, and
   multi-literal chains — inputs the regression test does not use — pass.

Deliverable: the repaired `/app/src` tree.