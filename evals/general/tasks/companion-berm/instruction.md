# Stale progress-indicator label after a dependency-resolution error

## Situation

`/app/src` is a shallow, pinned clone of the `poetry` repository from
`https://github.com/python-poetry/poetry`, checked out at upstream commit
`35eb5025dc7374db74ef26ce32a0e70f54d2e3b6` and installed from that tree in
editable (development) mode, so the `poetry` package you import is exactly the
checked-out source. The project's own interpreter lives at
`/opt/poetry-venv/bin/python`, with `pytest` and the project's own test
dependencies installed in it. There is **no network** at trial time: everything
you need is already in the image; `pip` and `git fetch` will not work.

## The bug

While poetry resolves dependencies it runs a small single-line progress
indicator that shows what it is currently doing (for example
`downloading something`). Activities are shown inside a scoped block: the
resolver enters the indicator's context, sets the current activity label, does
the work, and the label is supposed to disappear when the block exits.

But when the in-progress work **aborts with an exception** while it is still
inside that block, the activity label is not removed. The partially-finished
block exits, yet the label is left behind in the shared indicator state, so it
keeps being displayed on later, unrelated progress lines — even lines produced
long after the failed operation is gone. The cleanup only runs when the block
completes successfully.

A user hits this as follows: run a resolver-driven operation, force one
resolution step to fail mid-activity (for instance a network or resolution
error raised while a "downloading ..." label is active), and watch the stale
label follow subsequent progress output.

## Reproducing the failure

You must find the failing code yourself and write your own reproduction; do
not assume one already exists on disk, and do not rely on any existing test.
In the `poetry` source there is a small progress indicator whose per-activity
label is set and cleared through a Python context-manager API: an operation
enters the indicator's context, sets its current activity label, does its
work, and the context is supposed to clear the label when the block exits.
The bug lives entirely in how that context manager handles an exception
raised by the body of the with-block. You will know you have found the right
state when, after an aborted operation, the label you set is still visible to
code that runs after the block instead of having been cleaned up.

Write your reproduction as a standalone script at the literal path
**`/app/reproduce_indicator_leak.py`** that:

- imports and exercises the installed `poetry` package from `/app/src` (the
  resolver's progress indicator and its context-manager API), never a harness
  path, and runs under `/opt/poetry-venv/bin/python`;
- enters the indicator's context, sets an activity label, then raises an
  exception inside the block to abort the operation;
- after the aborted block, checks whether the stale activity label leaked to
  code outside the block;
- prints a clear, human-readable verdict naming the activity label;
- **exits 0 if and only if no stale label leaks after the aborted block, and
  exits nonzero otherwise.**

On the tree exactly as shipped (the bug still present) your script must exit
nonzero. Run it yourself to confirm:

```
cd /app && /opt/poetry-venv/bin/python reproduce_indicator_leak.py   # fails while bug present
```

## What you need to do

Fix the checked-out tree at `/app/src` so that, when an operation aborts with
an exception inside the indicator's block, the current activity label is
cleaned up and does not leak to code outside the block — while every other
behaviour of the indicator is preserved:

- a block that completes normally must still clean the label up (the happy
  path must keep working);
- after a block (normal or aborted), a subsequent, unrelated block must start
  with a clean label;
- the label shown during an active block must still be the one just set (the
  "downloading ..." line must still show while the operation runs).

Drive your work with the project's own test runner from `/app/src` using
`/opt/poetry-venv/bin/python`. The project's own existing resolver tests under
`/app/src/tests/puzzle/` are offline and fast; run them to make sure nothing
else breaks. Add your own tests if that helps you verify, but the verdict on
your fix is made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything you need is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- Leaves the working tree at the pinned commit, no history fetched, no tracked
  file deleted. The verifier checks that at least one tracked source file
  under `src/poetry/` is modified (fixing this means changing the project's
  source, not test files or configuration), that no tracked test file was
  changed, and that `/app/src` still supplies the installed `poetry` package.

## What the verifier checks

1. The tree is still at commit `35eb5025dc7374db74ef26ce32a0e70f54d2e3b6`, the
   working clone contains no other history, no tracked file was deleted, only
   tracked source files under `src/poetry/` are modified (at least one), no
   tracked test file was changed, and the installed `poetry` package still
   resolves to the checked-out tree at `/app/src`.
2. Your reproduction at `/app/reproduce_indicator_leak.py` genuinely detects
   the bug: copied onto a clean pre-fix tree it must fail, and against your
   repaired tree it must pass.
3. The project's own upstream regression test for this behaviour passes
   (extracted from the fix into `/opt/golden` at image build time).
4. The project's own existing resolver tests still pass.
5. Hidden cases over other exception types, normal-exit and re-entry paths, and
   the indicator's label formatting — inputs the upstream test does not use —
   pass.

Deliverable: the repaired `/app/src` tree and the reproduction script at
`/app/reproduce_indicator_leak.py`.
