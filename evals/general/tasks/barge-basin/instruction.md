# bandit logs an internal error while scanning valid Python

## The situation

`/app/src` is a shallow, pinned clone of **bandit** (`https://github.com/PyCQA/bandit`),
a security-oriented static analyzer for Python, checked out at upstream commit
`ad56c78f1e2f7d56fb3f75e8c2d78da85292d0e0` and installed from that tree in
editable (development) mode, so the `bandit` command-line tool and
`python3 -m bandit` execute exactly the checked-out source. Git, Python 3.12,
pip, pytest, stestr and the packages the project's own test configuration needs
are installed. There is **no network** at trial time: `pip` and `git fetch`
will not work; everything you need is already in the image.

## The symptom

A user scanning perfectly valid Python with bandit sometimes sees, mixed into
the scan output, an alarming line like

```
[main]	ERROR	Bandit internal error running: <some plugin> on file ./whatever.py at line 2: list index out of range
```

followed by a Python traceback whose last frame is
`IndexError: list index out of range`. The scan does not abort: bandit logs the
internal error to stderr, keeps going, and exits with the same status and the
same issue metrics as if nothing had gone wrong — which is exactly why it is so
easy for a user to miss. The affected behaviour: for one particular family of
valid call expressions, the analyzer that inspects how processes are launched
cannot cope and crashes internally on **every** scan of a file that contains
such a call. Valid Python should never make the analyzer crash internally.

## What you need to do

1. **Before changing anything**, find an input that provokes the internal
   error, and write your own failing reproduction as the deliverable
   `/app/repro.py` (contract below). Run it: while the bug is present it must
   fail.
2. Repair the analyzer in `/app/src` so that scanning the same input produces
   no internal error — the `Bandit internal error` log line must never appear
   for that input — while every other scan behaviour is unchanged: the issue
   findings, the metrics, the exit status and the scan of normal code must be
   exactly as they were before your repair.
3. Drive your work with the project's own test runner, from `/app/src`:

```
python3 -m stestr run --concurrency 1
```

   The whole project test suite (268 tests) is green at the pinned commit;
   keep it that way. You may add your own tests or sample files anywhere under
   `/app` if that helps you verify, but the verdict is made by the verifier,
   which checks things its own way.

## Deliverable contract — `/app/repro.py`

A self-contained reproduction of the internal error. It must:

- take no arguments and work from any current working directory (it must not
  depend on being invoked from a particular directory);
- create its own small Python source file that triggers the internal error
  (for example with a temporary file), scan it with the installed bandit
  itself, and print everything bandit wrote to stdout and stderr (bandit's
  diagnostics go to stderr);
- exit `0` if and only if the scan completed with no line containing
  `Bandit internal error` on bandit's stderr, and a non-zero status otherwise.

The verifier runs exactly this script twice: (a) against the repaired tree,
where it must exit `0`, and (b) with the pristine pre-fix tree from
`/opt/pretree` on the import path, where it must exit non-zero **and** print
the internal-error evidence — that is how the verifier proves your
reproduction genuinely demonstrates the bug rather than passing vacuously.

## Constraints

- Network is unavailable; everything needed is installed already.
- The repaired clone is a deliverable. Change only what the fix requires, in
  place. The verifier asserts: HEAD is still the pinned commit; the working
  clone contains exactly one commit (nothing was fetched, no history was
  added); no tracked file was deleted; no new files were added under `bandit/`;
  and the only modified tracked files are source files under `bandit/` (at
  least one such modification is present). In particular, do not edit anything
  under `tests/` or `examples/`, do not change build or install files, and do
  not add import-time wrappers such as `sitecustomize.py`/`usercustomize.py`:
  the fix must live in the checked-out source itself.
- Files under `/opt/pretree`, `/opt/golden`, `/tests` and `/solution` are
  harness-owned; do not touch them. You may *read* `/opt/golden` and
  `/opt/pretree`: both come from upstream and contain no answers to this task.
- `import bandit` must still resolve to the checked-out tree at `/app/src` (it
  does; do not reinstall, uninstall or move anything, and do not create a
  second bandit package anywhere else on the import path).

## What the verifier checks

1. Provenance: the tree is still at commit
   `ad56c78f1e2f7d56fb3f75e8c2d78da85292d0e0`, the working clone contains no
   other history, no tracked file was deleted, only source files under
   `bandit/` are modified (at least one), `import bandit` resolves to
   `/app/src/bandit`, and the unguarded buggy condition is gone from the
   source with a guard in its place — the fix must be in the code, not in a
   wrapper.
2. Your `/app/repro.py`: it must exit `0` on the repaired tree, and it must
   exit non-zero while printing the `internal error` evidence against the
   pristine pre-fix tree at `/opt/pretree`.
3. The project's own upstream regression material for this behaviour (the
   fix-commit revision of the project's functional test, kept out of the tree
   at `/opt/golden/` and overlaid onto a copy of the tree for the run) passes.
4. The project's own test suite still passes.
5. Hidden cases over trigger shapes the upstream material does not use pass on
   the repaired tree, and the verifier's own scans of those shapes show **no**
   `internal error` on the repaired tree — while the pristine pre-fix tree
   still shows the `internal error` on exactly those shapes, proving the
   repairs removed the crash and not merely papered over this one scan.

Deliverables: the repaired `/app/src` tree and `/app/repro.py`.