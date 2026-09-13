# F-string escaped braces corrupt the line that plugins see

## Situation

`/app/src` is a shallow, pinned clone of flake8 (`https://github.com/PyCQA/flake8`),
the modular Python source-code checker, checked out at upstream commit
`2a811cc4d2aaed3e8eb5a9f04f08ccc8af7c0791` and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
source. Python 3.12, `pytest`, and the packages the project's own configuration
resolves (pycodestyle 2.12.1, pyflakes 3.2.0, mccabe 0.7.0) are installed.
There is **no network** at trial time: everything you need is already in the
image; `pip` and `git fetch` will not work.

## The bug

flake8 lints a source file by first replacing the *contents* of every string
literal in a line with filler characters, and only then handing the resulting
"logical line" to each plugin. On Python 3.12 this step goes wrong for an
**f-string that uses escaped (doubled) curly braces**, i.e. `{{` and `}}` for
a literal `{` and `}` inside the f-string: the redaction step miscounts the
escaped braces, so the logical line it hands to plugins is garbled and
misaligned with the physical line — filler characters land in the wrong
places and raw characters from the original line leak through where filler
should be.

The symptom is visible to any plugin that reports content taken from the
linted line. For example, when linting a file whose only line is

```python
f'{{"{hello}": "{world}"}}'
```

a logical-line plugin that prints the line it was handed should receive the
correctly redacted form

```
f'xxx{hello}xxxx{world}xxx'
```

(replacement fields are kept verbatim, escaped braces become two filler
characters each, and every other literal character is one filler character).
Instead it is handed the corrupted, misaligned line

```
f'x{x{hello}xxxx{world}xx}'
```

## Reproducing the failure

```
python3 /app/probe_fstring_redaction.py
```

runs flake8 (with a small logical-line plugin that reports the line it
receives) on several samples and compares each reported line against the
correctly redacted form. While the bug is present it prints the mismatches
and exits with status 1.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that lines containing
f-strings with escaped curly braces are redacted correctly on Python 3.12 —
the logical line handed to plugins must match the correctly redacted form
shown above — and so that every other string-redaction behaviour is
unchanged (plain strings, f-strings without escaped braces, and non-string
parts of the line redact exactly as they did before).

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/ -q -p no:cacheprovider -o addopts=""
```

The whole project test suite is green at the pinned commit; keep it that way.
Add your own tests if that helps you verify (for example more f-string
shapes, or a guard that plain strings are unaffected), but the verdict on
your fix is made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that no history was fetched or added, that no tracked files were
  deleted, that the only modified tracked files are source files under
  `src/flake8/` (at least one such modification is present), and that
  `import flake8` still resolves to the checked-out tree at `/app/src` (it
  does; do not reinstall or move anything).

## What the verifier checks

1. The tree is still at commit `2a811cc4d2aaed3e8eb5a9f04f08ccc8af7c0791`,
   the working clone contains no other history (nothing was fetched or
   added), no tracked file was deleted, only source files under
   `src/flake8/` are modified (at least one), and `import flake8` resolves
   to `/app/src/src/flake8`.
2. The project's own upstream regression test for this behaviour passes
   (that test is kept out of the tree at `/opt/golden/` and copied in by the
   verifier).
3. The project's own test suite still passes.
4. Hidden cases over escaped-brace f-string shapes the regression test does
   not use pass, plus a guard that non-f-string redaction is unaffected.

Deliverable: the repaired `/app/src` tree.