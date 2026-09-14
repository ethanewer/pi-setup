# oakum-landfall

You are working inside a real open-source project: **setuptools**
(`pypa/setuptools`), checked out at a pinned historical commit in
`/app/src`. The working tree is detached at that commit and is fully
functional: the package is installed from this tree in *editable* mode, so
any change you make under `/app/src/setuptools/` is picked up by a fresh
Python process without reinstalling. There is a bug in this tree's
wheel-building machinery. Your job is to find it, fix it in the working
tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Python 3.12; `setuptools` 75.3.0 installed editable from `/app/src`
  (`setuptools.__file__` points into `/app/src`).
- `pytest` 8.4.2, `wheel` 0.44.0, `packaging`, `jaraco.path` and the rest
  of the project's test dependencies are already installed. `gcc` is
  installed (one of the project's test fixtures compiles a tiny C
  extension).
- The checkout in `/app/src` has **no git history**: it contains exactly
  one commit (the pinned one), detached. Do not commit, do not create
  branches, do not fetch, do not reset, do not touch `.git` at all — the
  tree must stay detached at the pinned commit with your changes only in
  the working files.
- The container is self-contained: do not attempt to download or install
  anything, and do not reach the git remote. Everything you need is baked
  in.
- `cpus = 1`: one vCPU. All builds and tests are short; they just run on
  one core.

## The bug (user-visible symptom)

`setuptools` builds Python wheels with the `bdist_wheel` command. The
distribution being built has a *name*. When that name is a plain lowercase
word without punctuation (e.g. `mypkg`), everything works: the produced
wheel file is called `mypkg-1.0-py3-none-any.whl` and the wheel contains a
metadata directory called `mypkg-1.0.dist-info/`, and other tools happily
map that file name back to the distribution.

When the distribution name instead contains **dots, upper-case letters, or
runs of separator characters** (e.g. `unicode.dist`), the produced wheel
file is called `unicode.dist-1.0-py3-none-any.whl` and the metadata
directory inside it is `unicode.dist-1.0.dist-info/` — the name is written
into the archive *verbatim*. That is not allowed: the wheel format
specification requires the distribution component of a wheel file name
(and of the `.dist-info` directory inside it) to be the project's
**canonical normalised name**: every run of `- . _` collapsed to a single
`-`, the result lower-cased, and every remaining `-` replaced with `_`. So
`unicode.dist` must come out as `unicode_dist`, both in the wheel file name
and in the `.dist-info` directory name — never `unicode.dist`.

The symptom as a user would report it: "I built a distribution whose name
contains a dot and my wheel file is named `unicode.dist-1.0-py3-none-any.whl`;
tools that derive the project name from the wheel file name don't recognise
my wheel at all. Distributions with upper-case letters in the name have the
same problem — the wheel keeps the case instead of the canonical
lower-cased name."

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/reproduce.py` — a self-contained Python 3 script that
   demonstrates the defect using the **installed copy of setuptools** (import
   `setuptools` and/or drive the `bdist_wheel` command; do not reimplement
   the name-normalisation logic yourself). Its contract:

   - It must exercise the installed setuptools and fail (exit non-zero, on
     an `AssertionError` or explicit failure that prints the offending
     name) **iff** the installed setuptools does **not** apply the canonical
     normalisation described above — e.g. it must fail whenever
     `unicode.dist` does not come out as `unicode_dist` in the wheel file
     name and in the `.dist-info` directory name.
   - It must exit 0 (after printing what it verified) iff the installed
     setuptools does apply the canonical normalisation.
   - It must not depend on the current working directory, must not touch
     anything outside a scratch directory of its own under `/tmp`, and must
     not require network access.

   On the **unfixed** tree this script must fail. Confirm that now, before
   fixing anything. (The verifier will run your script in both directions:
   once against a pristine buggy copy of the tree and once against your
   repaired tree, so it must genuinely exercise the installed setuptools —
   a script that only checks its own hand-written string logic does not
   satisfy the contract.)

2. **Fix the tree.** Make the change such that `/app/reproduce.py` passes
   (exit 0) and such that **both** the wheel file name and the `.dist-info`
   directory name use the canonical normalised distribution name for every
   distribution name (dots, upper case, runs of separators — not just your
   one input). Fix the mechanism, not one input. Note that the same defect
   is reachable through two different code paths that each build
   distribution-name filename components; both must end up canonical. Do
   not special-case your reproduction in a wrapper — the graded checks
   exercise the installed setuptools directly.

3. **Break nothing else.** The project's own test suite must stay green
   for the behaviour it covers: wheel building, `.dist-info` handling and
   the name-normalisation helpers. The tree includes the project's own
   regression tests for this exact behaviour — they fail right now and
   must pass after your fix. **Do not modify those regression tests**: the
   grader checks them byte-for-byte against pinned copies.

4. **The graded tree must differ from the pinned commit only where the fix
   requires it.** You may change the source files the bug lives in; you may
   not add, move, delete or reformat any other tracked file, and you may
   not leave stray untracked files under `/app/src` (Python byte-code
   caches are ignored). Your authored file `/app/reproduce.py` lives
   **outside** `/app/src`.

## Working loop (recommended)

1. **Reproduce**: import the installed package, call the machinery that
   turns a distribution name into a wheel file name with `unicode.dist`
   (and with an upper-case name like `Camel.Case`), and run a real
   `bdist_wheel` build of a scratch distribution under `/tmp` whose name
   contains a dot. Observe the non-canonical wheel file name and
   `.dist-info` directory name.
2. **Localise**: trace where the wheel file name and the `.dist-info`
   name are assembled, and where distribution-name components get
   "normalised" (and where they fail to). Understand why `Camel.Case`
   stays `Camel.Case` instead of becoming `camel_case` before you patch.
3. **Fix** with the smallest change, then re-run `/app/reproduce.py` and
   the project's regression tests.
4. **Prove nothing else broke**: run the project's own tests for wheel
   building and `.dist-info` handling from `/app/src`, e.g.:

   ```
   cd /app/src
   python3 -m pytest -q setuptools/tests/test_bdist_wheel.py setuptools/tests/test_dist_info.py
   ```

## Deliverables

1. `/app/reproduce.py` — your own failing reproduction, per the contract
   above. (Write it first, confirm it fails on the unfixed tree, then fix
   the tree, then confirm it passes.)
2. `/app/src` — the repository with your fix applied in the working tree,
   detached at the pinned commit, `.git` untouched.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone's object store, that the
  tree differs from the pinned commit only in the source files the fix
  requires (plus the twin regression-test files the image shipped, which
  must byte-match pinned copies), and that no stray untracked files remain
  under `/app/src`;
- require `/app/reproduce.py` to exist and to exit **non-zero** when run
  against a pristine buggy snapshot of the tree (baked into the image) and
  **zero** when run against your repaired tree — proving the symptom is
  real and your reproduction targets it;
- run the project's **own regression tests** for this behaviour (shipped
  with the tree, pinned) against your repaired tree and require them to
  pass;
- run a selection of the project's still-existing tests for the same area
  (`test_bdist_wheel.py`, `test_dist_info.py`, plus the doctests of the
  normalisation module) and require them all to pass;
- run authored hidden cases exercising the same code path from inputs the
  upstream regression tests do not use (further punctuation/case name
  shapes, and end-to-end wheel builds whose names contain dots and upper
  case);
- run a site-isolated probe that exercises the two name helpers directly
  from the tree, so that no wrapper, monkey-patch or site hook injected
  anywhere outside the tree can stand in for the fix.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.