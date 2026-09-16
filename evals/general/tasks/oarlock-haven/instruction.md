# monkeypatch.undo() re-raises errors from mutations that never happened

## Situation

`/app/src` is a shallow clone of `https://github.com/pytest-dev/pytest`, the
pytest testing framework, checked out (detached) at upstream commit
`efa117ad49ce197c5971b12310d53b73ed678d92` and installed in editable
(development) mode, so `import pytest` and `import _pytest.*` resolve to the
checked-out tree. Python 3.12 and the project's own development dependencies
(argcomplete, attrs, coverage, hypothesis, mock, numpy, pexpect, pytest-xdist,
pyyaml, requests, xmlschema, and their transitive dependencies) are installed.
There is **no network** at trial time: everything you need is already in the
image; `pip` and `git fetch` will not work.

## The bug

pytest's `monkeypatch` fixture offers `setattr`, `setitem`, `delattr`,
`delitem`, `setenv`, `delenv`, ... — calls that change something now and roll
the change back automatically when the test ends, through the fixture's
`undo()` bookkeeping.

Some of these calls can legitimately fail at runtime, and callers catch that
failure and continue. For example:

- `monkeypatch.setitem(mapping, key, value)` and
  `monkeypatch.delitem(mapping, key)` raise `TypeError` when applied to an
  immutable mapping, such as a `types.MappingProxyType`;
- `monkeypatch.delattr(obj, name)` raises `AttributeError` when the attribute
  cannot be removed from `obj` (for example a slot-class attribute, or a
  property without a deleter).

In each such case pytest still records the operation in its rollback
bookkeeping even though the mutation failed and nothing actually changed.
When `undo()` later runs — for instance during the fixture teardown at the end
of the test — pytest tries to roll back a change that never happened and
*re-raises the original exception* (the same `TypeError` or `AttributeError`)
in place of the harmless no-op the framework should perform:

```
monkeypatch.setitem(mapping, "x", 2)   # raises TypeError; the test catches it
... test keeps running ...
# teardown: monkeypatch.undo() re-raises the same TypeError
```

The user-visible symptom: a test that already handled the expected failure
fails a second time during teardown with the identical exception, this time
raised from `undo()` rather than from the original call — even though the
mutated-on object is unchanged and there is nothing to roll back.

Failed mutations should register nothing to undo: after a failed call,
`undo()` must be a quiet no-op, and a later `undo()` must roll back exactly and
only the operations that actually succeeded, restoring the value that was
there before each successful change.

## Reproducing the failure yourself

Before changing anything, write your own reproduction. It is a **deliverable**:

- Create `/app/repro_failed_undo.py` — a standalone Python script (stdlib plus
  the installed pytest; it must run with `python3 /app/repro_failed_undo.py`,
  no pytest runner needed) that performs at least one mutation which fails, in
  the way described above, and then calls `undo()`.
- The script must exit with status 0 **iff** the behaviour is correct:
  `undo()` after a failed mutation is a no-op, does not raise, and the
  mutated-on object is unchanged. It must exit nonzero while the bug is
  present (for example because that `undo()` call re-raises the stale
  exception).
- The verifier runs your script twice: once against the untouched pre-fix
  tree and once against your repaired tree. It must fail on the former and
  pass on the latter — that is what proves it actually exercises the bug.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a failed
`setitem` / `delitem` / `delattr` mutation records nothing to undo, and
`undo()` after such a failure is a harmless no-op, while every *successful*
mutation is still rolled back exactly as before — `undo()` restores the
previous value of each entry or attribute that was actually changed, and
restores entries/attributes that were actually deleted. Add tests of your own
if that helps you verify (for example more failure shapes, or guards that
successful mutations still roll back and that non-failing mappings keep their
old values after `undo()`), but the verdict on your fix is made by the
verifier, which also runs checks its own way.

Drive your work with the project's own test runner from `/app/src`:

```
cd /app/src && python3 -m pytest testing/test_monkeypatch.py -q -p no:cacheprovider
cd /app/src && python3 -m pytest testing/test_pytester.py -q -p no:cacheprovider
cd /app/src && python3 -m pytest testing/test_tmpdir.py testing/test_pathlib.py testing/test_recwarn.py -q -p no:cacheprovider
```

The project's own suite is green at the pinned commit; keep it that way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The repaired tree at `/app/src` and the reproduction script at
  `/app/repro_failed_undo.py` are the deliverables. Change only what the fix
  requires: the only tracked files you may modify are source files under
  `src/_pytest/` (at least one such modification must be present). Do not
  modify anything under `testing/`, do not delete tracked files, do not add
  new files inside the repository, do not add/remove/fetch git history, and
  do not change build files. Scratch files belong outside the repository
  (for example directly under `/app/`).
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch
  them.

## What the verifier checks

1. Provenance: the clone is still at the pinned commit, contains exactly one
   commit (nothing was fetched or added), the upstream fix is not reachable,
   only source files under `src/_pytest/` are modified (at least one), no
   tracked file was deleted, nothing under `testing/` or elsewhere was
   touched, and `import _pytest.*` still resolves to the checked-out tree.
2. Your reproduction script: it must fail against the pristine pre-fix tree
   and pass against your repaired tree.
3. The project's own regression test for this bug passes on your repaired
   tree. (That test is kept out of the tree at `/opt/golden/` and copied in by
   the verifier; you do not need to obtain it.)
4. The project's own test battery (the three commands above) still passes.
5. Hidden cases over failure shapes and rollback orderings that the upstream
   regression test does not use pass on your repaired tree.