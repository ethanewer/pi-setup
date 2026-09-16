# Freezegun PR/issue source receipt

This task was authored from the assigned repository row:

- CSV: `/Users/ethanewer/posttraining-2606/local/data/terminal_docs_v004/libraries_frameworks_github.csv`, row `freezegun,https://github.com/spulec/freezegun`
- Repository: https://github.com/spulec/freezegun
- License: Apache License 2.0, retained as `environment/files/freezegun_base/LICENSE`
- Reference: https://github.com/spulec/freezegun/pull/583
- Base revision: `c9bf52c5aa12ea1b5b8647a136a92504ea071f2f`
- Upstream repair revision: `8df34959e3b094f3190cb1a7191309296a1aaac8`
- Merge containing the repair: `92d61b3f5c31942a1039713574487bdcfcdbbfff`

## Material actually consulted

Using a fresh clone of the upstream repository at `/tmp/freezegun-upstream.3A2J1F`:

1. `git log --oneline --decorate -30` identified the recent PR #583 history.
2. `git show --format=fuller 8df34959e3b094f3190cb1a7191309296a1aaac8 -- freezegun/api.py tests/test_operations.py` showed the two-line control-flow repair and upstream regression tests.
3. `git show c9bf52c5aa12ea1b5b8647a136a92504ea071f2f:freezegun/api.py` confirmed the pre-fix independent `if self.as_kwarg` and its `else`.
4. `git show c9bf52c5aa12ea1b5b8647a136a92504ea071f2f:requirements.txt` and `setup.py` identified the runtime dependency on `python-dateutil`.
5. `git show c9bf52c5aa12ea1b5b8647a136a92504ea071f2f:LICENSE` confirmed Apache License 2.0.

## Reproduction evidence

The authored reproduction calls `freeze_time("2012-01-14", as_arg=True)` around a function with a positional and keyword-only argument, then checks an `as_kwarg` function. On the base revision, the first `if self.as_arg` invokes the function with the factory, then the later `if self.as_kwarg` is false and its `else` invokes the function again without the factory; the reproduction catches that failed second call and reports `BUILT FAIL` and `CALLS 1`. On the repair revision, changing that second `if` to `elif` makes the reproduction exit successfully with `BUILT PASS` and `CALLS 2`.

The package shipped in the task is the `freezegun/` source directory from the base revision plus the retained upstream `LICENSE`; it contains no fix history or answer-bearing git metadata. The verifier-owned copy is under `tests/fixtures/freezegun_pristine`, with a manifest and base commit file; no pristine ground truth is placed under writable `/opt` paths. The repair remains solely in the reference solution and is not copied into the agent environment.

## Verification performed

- Direct base archive: `FREEZEGUN_SOURCE=<base-archive> python3 environment/files/reproduce.py` printed `BUILT FAIL` and `CALLS 1` (exit 1).
- Direct fixed archive: the same command against the `8df3495` archive printed `BUILT PASS` and `CALLS 2` (exit 0); both hidden scripts passed against that fixed archive.
- Container reference run: `docker build --pull=false -t freezegun-issue-repair-local evals/general/tasks/freezegun-issue-repair/environment` succeeded, then `/solution/solve.sh && /tests/test.sh` printed `BUILT PASS`, `CALLS 2`, `REWARD 1`; the same verifier compared the fixture manifest to the pinned base and checked the reproduction's exact repaired and pristine output contracts.
- Static checks: `python3 evals/general/tools/qa_task.py --candidate evals/general/authoring/candidates/freezegun-issue-repair.json --static-only` returned status `draft` with `errors: []`; `python3 evals/general/tools/lint_tasks.py --task freezegun-issue-repair` reported `problems=0 notes=0`.
- No Harbor run was performed; parent runtime QA remains responsible for independent execution.
