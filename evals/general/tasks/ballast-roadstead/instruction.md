# `poetry debug resolve` crashes on platform-restricted packages

## Situation

`/app/src` is a shallow, pinned clone of the poetry repository
(`https://github.com/python-poetry/poetry`), the dependency manager for
Python, checked out at upstream commit `b760721672011534ca3607d17e3bf61a4dc6ed90`
in detached HEAD. The project is installed from that tree in editable
(development) mode into a dedicated virtual environment at
`/opt/poetry-venv`, so the code you import is exactly the checked-out source
and your edits take effect immediately. All of the project's own tooling is
ready: run everything with the venv's interpreters

```
/opt/poetry-venv/bin/python
/opt/poetry-venv/bin/pytest
```

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail. Everything you need is already in the image.

The project's `pyproject.toml` configures pytest with `addopts` that assume
extra plugins (`-n logical`), so run pytest with those overridden, exactly as
below:

```
cd /app/src && /opt/poetry-venv/bin/pytest tests/console/commands/debug/test_resolve.py -o addopts="" -p no:randomly
```

## The bug

`poetry debug resolve` is an internal command that resolves a set of packages
against the configured repositories and prints a summary table with one row
per resolved package. It does not install anything; it only shows what the
resolution produced. When it resolves a dependency that is restricted to
certain environments, the command **crashes**:

- For a package that carries an environment marker — for example a package
  that only supports a particular operating system, or a certain
  `python_version` range — the command prints the `Resolution results:`
  heading and then dies with

  ```
  IndexError: list assignment index out of range
  ```

  and a Python traceback, so the user never sees the dependency listing.
- For a package without such a restriction the command works fine and prints
  `name version` per resolved package.

The expected behaviour is that a package with an environment marker is
listed with its marker as an extra column, on the same row:

```
pathlib2 2.3.0 sys_platform == "win32"
```

while a plain package keeps printing exactly two columns:

```
msgpack-python 0.5.3
```

## Reproducing the failure

`/app/probe_resolve.py` drives the real `debug resolve` command machinery —
including a real resolution — against a package that is restricted to `win32`,
using the same in-memory package repository the project's own command tests
use, so it needs no network. Run it with the project venv:

```
/opt/poetry-venv/bin/python /app/probe_resolve.py
```

While the bug is present it crashes with the `IndexError` above (exit
status 1). You can also reproduce it yourself in a test of your own: the
project's own command tests (under `tests/console/commands/debug/`) show the
idiom — construct an in-memory `TestRepository`, add a package, give it an
environment marker, and execute the `debug resolve` command — and
`tests/console/conftest.py` documents the `CommandTester` fixtures.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. `poetry debug resolve` lists a package that carries an environment marker
   with the marker as a third column on its row (exactly as shown above) and
   no longer crashes;
2. a package without an environment marker is printed exactly as before —
   `name version`, two columns, no extra separator or empty column;
3. packages that show no marker today render exactly as they did before.

The tests in the tree are the spec; the project's own `debug resolve` tests
are the closest reference for the expected output. Drive your work with the
venv pytest invocation shown above. You may add new tests of your own to
verify your fix (e.g. more marker shapes), but do not modify or delete the
tracked test files that are already there, and delete nothing else either.

## Constraints

- Everything is offline; do not attempt network use.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, reinstall
  packages, or change build files. Do not delete or modify any tracked test
  file. New files are fine anywhere outside `src/poetry/` (a new test file,
  for example).
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the working clone contains no
  other history; the only differences from it are your minimal source change
  (at least one tracked file under `src/poetry/` modified, nothing deleted,
  no new files inside `src/poetry/`); and `import poetry` still resolves to
  the checked-out tree at `/app/src`.
2. The project's own regression test for this behaviour — the one asserting
  that a marked package is rendered with its marker — passes. The verifier
  holds a copy of the upstream regression test and runs it against your
  repaired tree, then runs the whole upstream test file for the debug resolve
  command (all four tests).
3. The project's own existing tests for the debug command area still pass.
4. Hidden cases exercise the same code path with markers and packages the
  upstream test does not use — an OS marker different to the upstream one, a
  `python_version` marker, a combined marker expression, a
  `platform_machine` marker, and a plain package that must keep exactly two
  columns.

Deliverable: the repaired `/app/src` tree.