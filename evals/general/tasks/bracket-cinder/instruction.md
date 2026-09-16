# Keyword values that mix text with placeholders must not crash

## Situation

`/app/src` is a shallow, pinned clone of the gallery-dl project
(`https://github.com/mikf/gallery-dl`), checked out at an upstream commit
that has the bug described below, exactly as upstream had the tree at that
point in history. Python 3.12 and pytest are installed. The project is plain
Python; its own tests add the repository root to `sys.path`, so no package
install step is needed — the code you import is the checked-out source.

There is **no network** at trial time: everything you need is already in the
image; `pip install` and `git fetch` will not work.

## The bug

gallery-dl has a *keyword evaluation* feature: when it is enabled (the
`keywords-eval` config option), a configured keyword value is treated as a
formatted string before it is used in filenames, URLs, and metadata files. A
user can write values that mix literal text with `{placeholder}` references —
for example a URL template such as

```
https://cdn.example.com/albums/{album_id}/{filename}
```

or a metadata value such as `posted on {post_time}`.

When such a value is combined with literal text on both sides of a
placeholder, and the placeholder resolves to a **non-text** value — a number,
a date/time object, or `None` — the program crashes mid-run with a
`TypeError` of the form

```
TypeError: sequence item 1: expected str instance, int found
```

(The number reported, e.g. `1`, varies with the template.)

The same keyword value works fine when it consists of only a single
placeholder with no surrounding text: `{filename}` by itself never crashes,
but `https://cdn.example.com/{filename}` does the moment `filename` is not a
string. This makes the failure appear randomly depending on the metadata of
the item being processed, which is what the upstream report described: the
download job aborts partway through a gallery, on whichever item first has a
non-text value in the referenced field.

## Reproducing the failure

```
python3 -m pytest test/test_formatter.py -q -p no:cacheprovider
cd /app && python3 /app/probe_fmt.py
```

`probe_fmt.py` formats several template strings the way the keyword
evaluation path does (it puts `/app/src` on `sys.path` itself, so it can be
run from any directory). Templates that mix literal text with a placeholder
whose value is an integer, a datetime or `None` raise the `TypeError` above;
the single-placeholder templates succeed. A one-liner for the same thing:

```
cd /app/src && python3 -c "from gallery_dl import formatter; f = formatter.parse('foo {t}', None, int); print(f.format_map({'t': 1262304000}))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that formatted keyword
values that mix literal text with `{placeholder}` references never crash,
regardless of what type a placeholder resolves to. A numeric timestamp such
as `1262304000` must render as `foo 1262304000`, a `None` must render as
`None`, and a date/time object must render as it does elsewhere in the
project (`str(...)` of the value). Behaviour that already works must keep
working exactly as it does today:

- a value consisting of only a single placeholder must keep returning the
  resolved value unchanged (it may legitimately be a non-text object),
- placeholder **format specs** such as `{ds:D%Y-%m-%dT%H:%M:%S%z}` keep
  producing the same text in both single- and multi-part templates,
- templates with the **default** formatting (no custom keyword evaluation)
  keep producing identical output.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest test/test_formatter.py -q -p no:cacheprovider
```

The whole existing formatter test file is green at the pinned commit (42
tests); keep it that way. Add your own tests if that helps you verify — for
example templates around other types, or several placeholders in one value —
but the verdict on your fix is made by the verifier, which runs its own
checks as well.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them. Do not modify anything else outside `/app/src` — in
  particular the Python installation, `pytest`, and the repository's own
  test files are all left exactly as the image provided them, and the
  verifier checks that.
- The verifier also asserts that the working tree remains at the pinned
  commit, that only the minimal set of tracked source files were modified,
  and that no new files were added inside the `gallery_dl/` package (you may
  create scratch files elsewhere, e.g. under `/app`).

## What the verifier checks

1. The tree is still at the pinned buggy parent commit, the upstream fix
   is not reachable from the working clone, the minimal tracked source
   surface was modified, the change is non-trivial, and no new files
   appeared inside `gallery_dl/` or anywhere else in the clone.
2. The project's upstream regression test for this bug (run with the
   project's own test runner) passes.
3. The project's own existing formatter test suite still passes, together
   with the other self-contained per-module suites that exercise the same
   machinery.
4. Hidden cases pass, including templates from the keyword-evaluation path
   (URL templates with numeric, `None` and date/time placeholders) and
   custom formatting functions the upstream test does not use.

Deliverable: the repaired `/app/src` tree.