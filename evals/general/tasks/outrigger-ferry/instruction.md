# outrigger-ferry

You are working inside a real open-source codebase: **Poetry** (the Python
dependency manager, `python-poetry/poetry`), checked out at a pinned
historical commit in `/app/src` and installed from that tree (an **editable
install**, so `import poetry` inside the interpreter resolves to
`/app/src/src/poetry` — editing the source in `/app/src` is what changes
what the interpreter sees). There is a defect in this tree's install-error
reporting. Your job is to write a failing reproduction, find the defect,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file or function to
change: localising the bug is part of the task.

## Environment

- Python 3.12. A project virtualenv with everything pre-installed lives at
  `/opt/poetry-venv`; use `/opt/poetry-venv/bin/python` and
  `/opt/poetry-venv/bin/pytest`. The working tree starts clean and
  detached at the pinned commit; it is writable by you, but **do not
  commit, fetch, push, rebase, add remotes, or otherwise touch `.git`**.
- The project's own tests live in `/app/src/tests/` and are self-contained
  (they use fixture-mocked repositories and never touch the network).
  Invocation notes: run pytest as `/opt/poetry-venv/bin/pytest <paths> -q
  -p no:randomly -o addopts="" --no-header`. (`-o addopts=""` and
  `-p no:randomly` neutralise the project's own pytest configuration;
  without them the run misbehaves.) This is a development-era snapshot, so
  the project's *full* test suite is **not** green in this environment for
  unrelated reasons: three tests in `tests/installation/test_executor.py`
  (`test_execute_executes_a_batch_of_operations` and both parameters of
  `test_execute_prints_warning_for_yanked_package`) and one test in
  `tests/installation/test_chef.py`
  (`test_prepare_directory_with_extensions`) fail because they need
  embedded wheels or a live PEP 517 build that this offline image does not
  provide. Every other test file runs cleanly. Run targeted files or
  single tests, not the whole suite.
- **No network** in this container. Everything needed is baked in; you
  cannot install packages.
- `cpus = 1`: one vCPU.

## The bug (user-visible symptom)

Poetry lets a project configure **build config settings** — extra arguments
passed to the build backend of an sdist/wheel it installs — under the
`installer.build-config-settings` configuration (keyed by package name).
When such a setting's value is a **single string** — for example

```
CC=gcc
```

as an environment-variable-style setting for a package that builds C
code — the value is meant to be handed to the build backend as one
option, and to be shown that way in error messages. It is not.

The symptom appears when an install **fails during the build step**: in
that case Poetry prints a remediation command the user is expected to copy
and run (of the form `You can verify this by running pip wheel
--no-cache-dir --use-pep517 [--config-settings='K=V' ...] "<package>"`).
When the failed package has a **plain-string** build config setting, that
printed command is **garbled**: instead of one
`--config-settings='CC=gcc'` option, the string has been taken apart into
its individual characters and you get a run of nonsense options, one per
letter:

```
... --config-settings='CC=g' --config-settings='CC=c' --config-settings='CC=c' ...
```

so the user cannot copy the shown command to retry the build. Settings
whose value is a **list of strings** are rendered correctly — one flag per
item — and packages with no build config settings are unaffected. Only
plain-string values are mangled, every time the build fails in this way.

The required, observable behaviour after a correct fix:

- a plain-string setting value like `"CC": "gcc"` produces exactly one
  whole-value flag `--config-settings='CC=gcc'` in the remediation pip
  command — the per-character garbage is gone;
- string values with spaces, digits or punctuation stay intact as one
  flag; an empty-string value produces one flag of the form
  `--config-settings='KEY='`;
- list-of-strings values keep producing one flag per item;
- the flags are assembled in the same order as the configured settings.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.py` — your own minimal reproduction of the
   symptom above. Its contract:

   - A plain Python script (standard library plus the `poetry` package
     from `/app/src` and its dependencies, no `pytest`); run it with
     `/opt/poetry-venv/bin/python /app/repro.py`.
   - It must drive Poetry's real install machinery (the `Executor` class
     and friends) through the error path described above: configure a
     package with build config settings that include at least one
     plain-string value (e.g. `"CC": "gcc"`) **and** at least one
     list-of-strings value (e.g. `"--build-option": ["--one", "--two"]`),
     make the build step fail the way the symptom describes, and print the
     remediation pip command Poetry produces. (Poetry's own tests stub the
     build backend at its failure boundary rather than building real
     packages; read them under `/app/src/tests/installation/` if you want
     an example of the shape — the package `simple-project` in
     `/app/src/tests/fixtures/simple_project/` is a ready local fixture you
     may reuse.)
   - It must **not** catch the symptom-instruction exceptions: the check
     must be on the *printed command text*. On the unfixed tree the printed
     command contains the per-character garbage; the script must therefore
     print the command and exit **non-zero**. On a correct fixed tree it
     must exit **0**.

     Concretely: exit `0` if and only if the printed output contains
     `--config-settings='CC=gcc'` (the whole string as one flag), does not
     contain any `--config-settings='C=C'`-style per-character fragment,
     and also contains `--config-settings='--build-option=--one'`. On the
     unfixed tree the first two conditions fail (garbage instead), so the
     script exits non-zero with the garbled command visible.
   - It must not depend on where it is run from and must not modify
     anything outside `/app` and `/tmp`.

   On the **unfixed** tree this script must fail. Confirm that now,
   before fixing anything: `/opt/poetry-venv/bin/python /app/repro.py;
   echo $?` should print the garbled pip command (traceback optional) and a
   non-zero exit status.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.py` passes (exit 0, printed command not garbled), while
   list-valued settings still render one flag per item. Fix the mechanism,
   not one input: the same defect is reachable with any single-string
   value — including empty strings, values with spaces, digits or
   punctuation — and the grader exercises these.

3. **Break nothing else.** Everything else must keep working exactly as
   before: all the project's previously-passing tests must stay green.

4. **The graded tree must be byte-identical to the pinned commit except
   for the source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; do not modify anything under
   `/app/src/tests/` or any build/packaging file; if you create scratch
   files to investigate, delete them before you finish; make no commits.
   The grader compares every file's bytes against the pinned commit's own
   blobs, so cosmetic side-changes also fail. Your two authored files
   `/app/repro.py` and `/app/summary.md` live **outside** `/app/src` and
   are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Grading

- `/app/repro.py` is executed against the **repaired** tree: it must exit 0
  and print the whole-string flag.
- `/app/repro.py` is executed against a **pristine unmodified copy** of the
  same code, kept in the image for exactly this purpose: it must fail
  there (proving the reproduction is real and targets the symptom).
- The project's own regression test for this bug (taken from the fix-era
  source) is run against the repaired tree and must pass — including its
  assertion that array values keep one flag per item. The same regression
  test must fail against the pristine pre-fix copy.
- The project's previously-existing test files are run and must stay
  green.
- Three hidden cases exercise the same behaviour from inputs the upstream
  regression test does not use.

A good working loop: reproduce with `/app/repro.py` and watch it fail;
read the installed package source under `/app/src/src/poetry/` and the
project's own tests under `/app/src/tests/installation/` to find how the
remediation pip command is assembled; make the smallest change in the
tree; re-run `/app/repro.py` until it passes; then re-run the project's
relevant test files (e.g. `cd /app/src &&
/opt/poetry-venv/bin/pytest tests/installation/test_executor.py -q -p
no:randomly -o addopts="" --no-header --deselect
tests/installation/test_executor.py::test_execute_executes_a_batch_of_operations
--deselect
tests/installation/test_executor.py::test_execute_prints_warning_for_yanked_package`)
and confirm nothing else broke.

Do not touch files under `/opt/golden`, `/opt/pre-fix-poetry`, `/tests` or
`/solution` — they are harness-owned.