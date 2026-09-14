# clew-bulkhead

You are working inside a real open-source codebase: **SciPy** (the
scientific-computing library, `scipy/scipy`), checked out at a pinned
historical commit in `/app/src` (the working tree starts clean, and SciPy is
already built and installed **from this very tree** into the image's Python
environment). There is a bug in this tree's computational-geometry machinery.
Your job is to find it, fix it in the working tree, and prove the fix with
the project's own test tooling. You are deliberately **not** told which file
or function to change: localising the bug is part of the task.

## Environment

- Python 3.12 with numpy and SciPy **built from `/app/src`** installed into
  the environment. The build is **warm**: a full build ran at image-build
  time with a persistent build directory at `/work/sci-build`, so your
  rebuilds after source edits recompile only what changed.
- To rebuild after an edit, run, from `/app/src`:

  ```
  cd /app/src && python3 -m pip install -e . --no-build-isolation \
      --config-settings=builddir=/work/sci-build
  ```

  This is incremental and fast: the warm build directory is baked into the
  image, so on this tree a rebuild that touches only the module you edited
  takes seconds even though the machine has **only one vCPU** (`cpus = 1`).
  Do not reinstall or upgrade numpy, cython or anything else; rebuilding
  the whole package from scratch is not feasible in the time budget.
- **There is no network** in this container. Nothing can be downloaded:
  every dependency, including the SciPy build toolchain (cython, meson,
  ninja, pybind11, pythran, pytest), is already installed and pin-locked
  (`PIP_NO_INDEX=1`). Do not attempt to `pip install`, fetch or update
  anything.
- The tree lives at `/app/src` and is writable by you (root and uid 1000
  both work). **Do not commit, fetch, push, rebase, reset, cherry-pick or
  otherwise modify `.git`** — the working tree is detached at the pinned
  commit and must stay there. Do not `git checkout <sha> -- <path>`: it
  stages files, and staging is forbidden.
- **Importing and testing**: Python must NOT run with the current working
  directory inside `/app/src` (SciPy refuses to import from inside its own
  source directory). Run your reproduction from `/tmp` or `/app`, and run
  the project's test suite from outside the tree too, naming the test file
  by path:

  ```
  cd /tmp && python3 -m pytest /app/src/scipy/spatial/tests/test_qhull.py -q
  ```

  The regression file for the geometry code involved is
  `scipy/spatial/tests/test_qhull.py`. The numeric-thread environment
  variables are already pinned to 1 thread.
- The tree's working copy must be kept git-clean: anything you
  create to investigate (logs, core dumps, scratch files) must be placed
  under `/tmp` and deleted before you finish; the grader compares every
  file in `/app/src` byte-for-byte against the pinned commit.

## The bug (user-visible symptom)

The library's convex-hull constructor, `scipy.spatial.ConvexHull`, is
documented to take `points`, a 2-dimensional array whose rows are the
point coordinates. When a user passes an array that is **not** a 2-D
matrix of samples, the constructor does not reject it with a clear,
catchable error. Instead the call misbehaves internally and crashes:

- passing a **flat 1-D array** (e.g. `.reshape(-1)` of some data, or a
  vector of values) fails with an internal `IndexError: tuple index out
  of range` — an exception from deep inside the construction code that
  says nothing about the real mistake;
- passing a **3-D or higher-dimension array** (for example a stack of
  point clouds with shape like `(5, 1, 3)`) can go much further before
  failing: the process **segfaults** outright (the interpreter dies with
  a signal; exit code 139 / core dump), because the malformed array is
  handed to the compiled geometry engine which walks off the end of the
  buffer.

A user who passes misshapen data gets a hard crash or a meaningless
exception instead of a usable error message telling them the input must be
a 2-D array of point coordinates.

The affected behaviour: `ConvexHull` constructed from any non-2-D
`points` array must fail cleanly and immediately with a single, catchable
`ValueError` explaining that the input must have the 2-D shape
`(npoints, ndim)` — with no `IndexError` and, above all, no crash of the
Python process. Valid 2-D input must keep working exactly as before.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It is an executable shell script (`#!/bin/sh` or `#!/bin/bash`) that
     runs a short Python snippet using the environment it is invoked
     under (it must **not** hardcode an absolute interpreter path or a
     `PYTHONPATH` — it must work when the harness prepends a different
     site-packages directory to `PYTHONPATH` and re-runs it).
   - The snippet imports `scipy.spatial.ConvexHull`, builds a **flat 1-D**
     numpy array as the input (e.g. `np.ones(5)` — this is the input shape
     that misbehaves internally on the unfixed tree without a hard
     segfault), calls `ConvexHull(points)`, and expects it to fail.
   - The script exits **0 if and only if** the constructor rejected the
     input with a **clean `ValueError` whose message states the input must
     be a 2-D array of shape `(npoints, ndim)`** (i.e. the error a correct
     library raises). It must print the error message to stdout.
   - The script exits **non-zero** for every other outcome: the call
     succeeding, any other exception type (including the internal
     `IndexError` the unfixed tree raises), a crash, or an import failure.
   - It must run from any working directory and must not modify
     `/app/src` or anything outside a scratch directory of its own.

   On the **unfixed** tree this script must fail (the internal `IndexError`
   path), so run and confirm it before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exits 0 with the clean `ValueError` message),
   also after a fresh incremental rebuild. Fix the mechanism, not just one
   input: the same defect is reachable with a vector, a 4-D block, a 0-D
   scalar, or any other non-2-D shape (see Grading). Do not merely wrap
   the call in a script — the graded checks exercise the compiled code
   path directly.

3. **Break nothing else.** Everything else must keep working exactly as
   before: valid 2-D point clouds of any size and dimension must produce
   the correct convex hull, masked-array and NaN inputs must still be
   rejected with `ValueError`, and the project's own geometry test file
   `scipy/spatial/tests/test_qhull.py` must stay green. Run it after your
   fix.

4. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed (file, function, before/after behaviour), and how you
   verified the fix.

## Grading

- The graded tree must be byte-identical to the pinned commit except for
  the **single source file where the bug lives**. Do not add, move,
  delete, rename or reformat any file; if your investigation creates
  scratch files (including core dumps), delete them before you finish;
  make no commits; do not modify the test file, the build configuration,
  or any other file. The grader compares every file's bytes against the
  pinned commit's own blobs, so cosmetic side-changes also fail. Your two
  authored files `/app/repro.sh` and `/app/summary.md` live **outside**
  `/app/src` and are fine.
- The verifier rebuilds the tree from the source you delivered, runs your
  `/app/repro.sh` — it must pass on your repaired tree and must have
  failed on the pristine pre-fix tree — runs the project's own regression
  test for this bug, runs the existing geometry test file, and then runs
  hidden cases that hit the same code path from non-2-D inputs your
  reproduction does not use, some of them drawn from a random seed so no
  fixed input list can be matched ahead of time, plus a valid 2-D case
  that must still produce the correct hull. A fix that only special
  cases one input shape will fail some of them; so will a fix that
  rejects any input that used to work.

## Working loop (recommended)

1. **Reproduce** the crash: write a one-line script from the symptom
   description — build the input with numpy yourself (a flat 1-D array
   works: it misbehaves internally without a hard segfault; a 3-D shape
   from the symptom description in a subprocess so a segfault does not
   kill your shell) — and observe the internal `IndexError`. Read the
   traceback and the source it points at to understand *where in the
   construction the array is assumed 2-D*.
2. **Localise** the bug: trace what the constructor does with the input
   array between the moment it arrives and the first indexing operation,
   and where the raw buffer then reaches the compiled geometry engine.
3. **Fix** with the smallest possible change in that one source file,
   rebuild with the command above, and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run
   `cd /tmp && python3 -m pytest /app/src/scipy/spatial/tests/test_qhull.py -q`
   and confirm it is green on your fixed tree.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing-before/fixed-after reproduction, per
   the contract above.
3. `/app/summary.md` — a non-empty write-up of bug, change and
   verification.