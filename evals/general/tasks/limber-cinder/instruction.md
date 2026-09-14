# limber-cinder

You are working inside a real open-source codebase: **Jinja** (the
templating engine, `pallets/jinja`), checked out at a pinned historical
commit in `/app/src` and installed from that tree (an **editable install**,
so `import jinja2` inside the interpreter resolves to
`/app/src/src/jinja2` — editing the source in `/app/src` is what changes
what the interpreter sees). There is a behavioural regression in this
tree's rendering runtime. Your job is to write a failing reproduction, find
the defect, fix it in the working tree, and prove the fix with the
project's own test tooling. You are deliberately **not** told which file or
function to change: localising the bug is part of the task.

## Environment

- Python 3.12 with `jinja2` installed editable from this very tree
  (`/app/src`). The working tree starts clean and detached at the pinned
  commit; it is writable by you, but **do not commit, fetch, push, rebase
  or otherwise touch `.git`**.
- `pytest` 7.4.3 is installed. The project's own tests live in
  `/app/src/tests/` and are self-contained (they never touch the network).
  Note: this is a development-era snapshot, so the project's *full* test
  suite is **not** green in this environment for two unrelated era issues
  (`tests/test_debug.py` and `tests/test_loader.py` fail for reasons that
  have nothing to do with this bug). Every other test file runs cleanly and
  takes about two seconds; run targeted files or single test classes, not
  the whole suite.
- **No network** in this container. Everything needed is baked in; you
  cannot install packages.
- `cpus = 1`: one vCPU.

## The bug (user-visible symptom)

Since the previous major version, templates that probe optional data with
the **membership operator** behave differently when the probed value is not
defined. In the previous major version, checking membership against a name
that has not been given a value simply evaluated the test to false and the
template rendered normally — for example a template containing

```
{{ "admin" in user_roles }}
```

with `user_roles` not defined rendered `False`. On this tree, the same
template **aborts rendering** with a

```
jinja2.exceptions.UndefinedError: 'user_roles' is undefined
```

and produces no output. Every membership test against a missing value is
affected the same way — `in` and `not in` in interpolations, and `in` /
`not in` inside `{% if %}` conditions — instead of evaluating to `False`
(or to `True` for `not in`, so that `{% if "x" not in missing %}` takes the
true branch).

**Users who explicitly opted into strict-undefined mode are the deliberate
exception**: in that mode, operations on undefined values are documented to
raise, and a membership test against a strict-undefined value must keep
raising `UndefinedError`. The required, observable behaviour after a correct
fix is:

- default undefined (`Environment()`): `{{ "foo" in missing }}` renders
  exactly `False`; `{{ "foo" not in missing }}` renders exactly `True`;
  `{% if "a" in missing %}` evaluates its condition false (and
  `not in` evaluates true); the same holds when the undefined value is
  reached through a chain (e.g. `missing.bar`), when it is the undefined
  value returned for a missing attribute of a real object (e.g.
  `foo.missing` with `foo=42`), and for the project's other undefined
  variants (`ChainableUndefined`, `DebugUndefined`).
- strict undefined (`Environment(undefined=StrictUndefined)`): a
  membership test against an undefined value still raises
  `jinja2.exceptions.UndefinedError`.
- everything else keeps working exactly as before.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.py` — your own minimal reproduction of the
   symptom above. Its contract:

   - A plain Python script (standard library plus `jinja2` only, no
     `pytest`).
   - It renders a template that applies the membership operator
     (`in` / `not in`) to a name you leave **undefined**, using the
     **default** undefined behaviour, and prints whatever the render
     produces.
   - It must **not** catch exceptions: on the unfixed tree the render
     raises `UndefinedError`, which naturally makes the script exit
     non-zero.
   - It exits `0` if and only if the render succeeded and produced exactly
     the string `False`.
   - It must not depend on where it is run from and must not modify
     anything outside `/app` and `/tmp`.

   On the **unfixed** tree this script must fail (the render raises). Confirm
   that now, before fixing anything: `python3 /app/repro.py; echo $?`
   should print a traceback and a non-zero exit status.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.py` passes (exit 0, output `False`), while strict-undefined
   membership still raises. Fix the mechanism, not one input: the same
   defect is reachable with `not in`, inside conditions, for chainable and
   debug undefined values, and for membership against a missing attribute
   of a real object — the grader exercises all of these.

3. **Break nothing else.** Everything else must keep working exactly as
   before: all the project's previously-passing tests must stay green.

4. **The graded tree must be byte-identical to the pinned commit except
   for the source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; do not modify anything under `/app/src/tests/`
   or any build/packaging file; if you create scratch files to investigate,
   delete them before you finish; make no commits. The grader compares
   every file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail. Your two authored files `/app/repro.py` and
   `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Grading

- `/app/repro.py` is executed against the **repaired** tree: it must exit 0
  and print `False`.
- `/app/repro.py` is executed against a **pristine unmodified copy** of the
  same code, kept in the image for exactly this purpose: it must fail there
  (proving the reproduction is real and targets the symptom).
- The project's own regression test for this bug (taken from the fix-era
  source) is run against the repaired tree and must pass — including its
  assertion that strict-undefined membership still raises.
- The project's previously-existing test files are run and must stay green.
- Four hidden cases exercise the same behaviour from inputs not used by the
  upstream regression test.

A good working loop: reproduce with `/app/repro.py` and watch it fail;
read the installed package source under `/app/src/src/jinja2/` to find how
the default undefined value implements (or fails to implement) membership;
make the smallest change in the tree; re-run `/app/repro.py` until it
passes; then re-run the project's relevant test files
(`python3 -m pytest tests/test_api.py::TestUndefined tests/test_api.py::TestStrictUndefined -q`
uses the tree's own tests — note that the tree's own copy of one of them
still asserts the old behaviour, so prefer reasoning about the *required*
behaviour above and the symptom it describes) and confirm nothing else
broke.