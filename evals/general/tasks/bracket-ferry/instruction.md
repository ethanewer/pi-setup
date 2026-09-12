# `pip show` crashes on packages with incomplete metadata

## Environment

- A development checkout of the **pip** source tree is at **`/app/src`**, at
  the exact revision this task was measured against. Because pip uses a
  nested `src` layout, the package itself is under `/app/src/src`.
- The container has **no network**. Do not try to `pip install`, `git fetch`
  or download anything; every dependency the project's test suite needs is
  already installed (pytest, pytest-socket, installer, scripttest,
  virtualenv, werkzeug).
- To drive the checkout's own pip instead of the one the base image ships:

  ```bash
  cd /app/src && PYTHONPATH=src python3 -m pip --version
  ```

  With `PYTHONPATH=src` the checkout wins, so any edit under `/app/src` takes
  effect immediately. Verify a change with

  ```bash
  cd /app/src && PYTHONPATH=src python3 -m pytest tests/unit/... -q
  ```

  which uses the project's own pytest configuration (including its test-time
  network guard). Focused unit tests run in seconds.
- The machine is budgeted at one CPU; everything here is pure Python.

## The bug

When a user asks pip for information about an installed package whose
metadata does not include a `Metadata-Version` header, `pip show` aborts with
a raw Python traceback (`invalid literal for int() with base 10: ''`) before
printing any of the package's fields, so the command is unusable for such
packages. Any distribution shipped with incomplete or legacy metadata
triggers it, and there is currently no way to get the package's details at
all.

To see it yourself, make a throwaway "installed" distribution on a directory
you add to `sys.path` (a dist-info directory whose `METADATA` file simply
omits the `Metadata-Version` header), then run the checkout's `pip show`
against it:

```bash
mkdir -p /tmp/fakepkgs/demo_pkg-1.0.dist-info
printf 'Name: demo-pkg\nVersion: 1.0\nSummary: legacy metadata, no version\n' \
  > /tmp/fakepkgs/demo_pkg-1.0.dist-info/METADATA
cd /app/src && PYTHONPATH=src:/tmp/fakepkgs python3 -m pip show demo-pkg
```

## What you must deliver

Make `pip show` (the checkout's `pip show`, i.e. the code under `/app/src`)
**work for such packages**: it must print the package's fields (`Name`,
`Version`, `Summary`, `Home-page`, `Author`, ..., `Requires`,
`Required-by`) instead of crashing, for any package whose metadata lacks a
`Metadata-Version`.

Keep the existing version-dependent behaviour working for packages that *do*
carry a `Metadata-Version`: the printed licence line already depends on that
value, and that logic must keep working for every package that has one.

The acceptance does three things:

1. runs the project's own regression test for this exact bug (this test
   exercises the show command's result-printing path with packages whose
   `Metadata-Version` is the empty string, and with normal ones) — it must
   pass;
2. runs a slice of the project's own existing unit test suite (the command
   registry and the metadata layer) to prove nothing else broke — it must
   still pass;
3. checks that the repository is otherwise untouched: the **only** change
   under `/app/src` may be the fix itself. Do not add, rename or delete any
   other tracked or untracked file in the repository, and do not change the
   committed revision. Use `/tmp` for scratch files.

Where in the tree the fix belongs, what exactly one edits, and how the
condition is handled are **your call** — the source, the test suite and
`git` history inside `/app/src` are there for you to inspect. You are
expected to reproduce the crash, locate the mistake and fix it for real;
patching site-packages, the interpreter, or anything outside `/app/src` does
not count.

## Deliverable summary

- A fixed `/app/src` tree (the pip checkout): the bug gone, the project's
  own tests green, nothing else modified.
- Nothing else. No report file, no new scripts anywhere under `/app/src`.