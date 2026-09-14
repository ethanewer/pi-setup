# Pylint crashes with a fatal internal error on empty-tuple type-argument subscripts

## Situation

`/app/src` is a shallow, pinned clone of **Pylint** (`https://github.com/pylint-dev/pylint`),
the Python code checker, checked out at upstream commit
`92b631fac22e503e9520fb5280929499b6787093` and installed from that tree in
editable (development) mode, so `python3 -m pylint` executes exactly the code in
`/app/src`. Python 3.12.13 is provided, together with `pytest` and the project's
own test dependencies (astroid 4.2.0b5, pytest 8.4.1, …), already installed.
There is **no network** at trial time: everything needed is in the image, and
`pip` and `git fetch` will not work.

Note: the project's own `pylintrc` (automatically picked up when Pylint runs
with the repository root as the working directory) enables a set of extension
plugins, among them the *typing* extension (`pylint.extensions.typing`). The
same extension can be enabled explicitly with `--load-plugins=pylint.extensions.typing`.

## The bug

When the typing extension is enabled, checking a source file that contains a
**type annotation that subscripts `Generator` (or `AsyncGenerator`) with an
empty tuple** makes the checker crash in the middle of the run with an internal
`IndexError`. For example, a module containing

```python
import collections.abc as ca

x: ca.Generator[()]
y: ca.AsyncGenerator[()]
```

ends its run with a Python traceback and a fatal-error report instead of a lint
report:

```
F0002: ... Fatal error while checking ...
```

and Pylint exits with a non-zero status, so the whole file is never actually
checked. Files that subscript these types with real arguments, e.g.
`x: ca.Generator[int, None, None]`, are checked fine; they must keep working,
and the extension must keep reporting `unnecessary-default-type-args` for them,
suggesting the shortened form `ca.Generator[int]`. Without the typing extension
enabled, files containing `ca.Generator[()]` are checked without any problem, so
the fault is specific to the extension's checking path.

## What you need to do

1. **Write a failing reproduction** as a single Python script at the literal
   path `/app/reproduce.py` (one of the deliverables). The script must invoke
   the installed Pylint (`python3 -m pylint`) on a small source file it creates
   itself (for example in a temporary directory), where that source file
   contains an annotation that triggers the crash, and Pylint must run **with
   the typing extension enabled** (`--load-plugins=pylint.extensions.typing`,
   or by running from `/app/src` where the project's own `pylintrc` loads it)
   and **with the `unnecessary-default-type-args` check enabled**
   (`--disable=all --enable=unnecessary-default-type-args`).
   Contract for the script:
   - it prints a short human-readable diagnostic describing what it ran and the
     outcome;
   - it exits with status **0 exactly when Pylint completes without a fatal
     internal error**;
   - it exits with a **non-zero status when Pylint crashes with the fatal
     internal error** (using the exit status Pylint itself produced is fine).

2. **Fix the bug in `/app/src`** so that any file containing empty-tuple
   subscripts `Generator[()]` / `AsyncGenerator[()]` (for `Generator` and
   `AsyncGenerator`, whether reached through `collections.abc` or through the
   `typing` module) is checked normally: no crash, no fatal-error notice. The
   extension's existing behaviour must be unchanged: subscripts with `None`
   defaults such as `ca.Generator[int, None, None]` still emit
   `unnecessary-default-type-args` with the `ca.Generator[int]` suggestion, and
   files without such annotations produce no messages at all. The fix must live
   in the source tree itself and must address the cause, not only mask the
   crash: the verifier re-runs your reproduction against a pristine copy of the
   un-fixed checking code (where it must fail) and against your repaired tree
   (where it must succeed), and it runs the project's own regression test for
   this behaviour against the repaired tree.

3. Drive your work with the project's own test runner, from `/app/src`:

   ```
   cd /app/src && python3 -m pytest tests/test_functional.py -k "typing or redundant_typehint" -o addopts="" -q -p no:cacheprovider
   ```

   These typing-extension functional tests are green at the pinned commit; keep
   them that way.

## Constraints

- No network; everything needed is already installed.
- The deliverables are the repaired `/app/src` tree and the `/app/reproduce.py`
  script. Change only what the fix requires, in source files under the Pylint
  package (`/app/src/pylint/`). Do not modify or delete any tracked test,
  build or configuration file, do not add new files anywhere under
  `/app/src` (the verifier rejects untracked files in the working tree;
  only innocuous caches like `__pycache__`/`.pytest_cache` are tolerated),
  and do not rewrite history, add remotes or fetch. In particular, do not
  drop `conftest.py` or `sitecustomize.py` files into the tree or into
  `/tests` to intercept the checks: `/tests` is re-uploaded at verification
  time and its files are content-pinned, and any interception file left in
  the tree fails the provenance check. The working tree must stay at the
  pinned commit `92b631fac22e503e9520fb5280929499b6787093`, and the
  clone's history must stay at exactly that one commit.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch them.

## What the verifier checks

1. Tree provenance: HEAD is still the pinned commit, the clone holds exactly
   that one commit, no tracked file was deleted, modified tracked files are
   confined to Pylint package sources with at least one modification, no new
   untracked file was left in the working tree, the fix is present in the
   source tree itself (a workaround applied outside the source, one that only
   swallows the exception, or a decoy guard hidden in a comment fails this
   check), the reproduction exists, and `import pylint` resolves to
   `/app/src/pylint/__init__.py`.
2. Your reproduction, run against a pristine copy of the un-fixed checking
   code, crashes with the fatal internal error (proving it exercises the bug),
   and run against your repaired tree, completes cleanly with exit status 0.
3. The project's own regression test for this behaviour (extracted from
   upstream into `/opt/golden/`, kept out of the tree) passes against your
   repaired tree.
4. The project's own typing-extension functional tests pass
   (`pytest tests/test_functional.py -k "typing or redundant_typehint" ...`).
5. Hidden cases over empty-tuple subscript shapes, code positions and
   extension-loading guards that the regression test does not use.