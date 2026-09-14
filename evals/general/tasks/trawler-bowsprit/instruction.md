# Setuptools artifact names silently drop part of the declared version

## Situation

`/app/src` is a shallow, pinned clone of the setuptools repository
(`https://github.com/pypa/setuptools`), checked out in detached HEAD. It was
installed **editable** (`pip install -e .`), so `import setuptools` in any
python you run resolves to the checked-out tree at `/app/src` — edit the
tree and your edit takes effect immediately, with no reinstall and no
rebuild.

Everything is installed and works fully offline: python 3.12, the project's
own test suite (`python3 -m pytest`), the `build` package (so
`python3 -m build --no-isolation` works), pip, git (clone, diff, grep, log,
status, worktree all work). There is **no network** at trial time: `git
fetch`, `curl`, pip installs and any other network use will fail.

## The bug

Every artifact setuptools produces is named from the project's release
name — the project name plus the version it declares (e.g. a project named
`foo` with version `1.0` is released as an archive named `foo-1.0.tar.gz`).
In this checkout, the version component of those names is being rewritten
into a normalized shorthand **before** it reaches the file name, so the
artifact names do not contain the version the project actually declares:

- a project that declares `version = "1.0"` produces `dist/foo-1.tar.gz`,
  not `dist/foo-1.0.tar.gz`;
- a project with **no declared version at all** gets setuptools' default
  version `0.0.0`, and its archive is named `dist/foo-0.tar.gz` instead of
  `dist/foo-0.0.0.tar.gz`;
- `2.3.0` becomes `2.3`, `1.0b1` becomes `1b1`, and so on: trailing zeros
  and similar normalizations are applied to the *name* even though the full
  version string is recorded intact inside the archive and in the
  `PKG-INFO`/`.egg-info` metadata.

The names therefore disagree with the project's own metadata, which breaks
release tooling, artifact matching, and anyone reading a download
directory. The version must appear in artifact names **exactly** as
declared — no normalization, no collapsing.

## What you need to do

Deliverables, both of which must exist before you are done:

1. `/app/reproduce.py` — **your own failing reproduction**. A single
   self-contained python script that, run as `python3 /app/reproduce.py`:

   - demonstrates the bug through setuptools' own machinery: create a
     scratch project in a temporary directory, build its source distribution
     with the project's own tooling (`python3 -m build --no-isolation
     --sdist`), and assert that the produced archive (`dist/…tar.gz`) is
     named with the declared version in full and not with a collapsed form;
     also assert, for a handful of declared versions (including `0.0.0`,
     `1.0` and `2.3.0`), the release-name string those basenames are derived
     from, however you discover to derive it;
   - exits with a non-zero status and a readable message **while the bug
     exists** (on this checkout, before you fix anything);
   - exits with status 0 once artifact names preserve the declared version.

   Write it, run it, and keep its failure output *before* you start fixing.
   Use the installed setuptools exactly as the interpreter resolves it — do
   not hardcode any import path and do not inspect the tree's git status
   from inside the script.

2. `/app/src` — the fixed tree. Fix the bug in the checked-out tree using
   only the project's own code as the surface. The fix is small and local.
   When you are done:

   - `python3 /app/reproduce.py` exits 0;
   - the project's own tests pass. Run enough of them to be sure you broke
     nothing else, e.g.:

     ```
     cd /app/src && python3 -m pytest -q setuptools/tests/test_config_discovery.py setuptools/tests/test_sdist.py setuptools/tests/test_egg_info.py setuptools/tests/test_wheel.py
     ```

     Caveat: this checkout is a pre-fix snapshot, so it contains *one* test
     whose expectation encodes the collapsed name (a trailing-shorthand
     archive name for the default version). That expectation is part of the
     buggy behaviour, not ground truth — the verifier runs the corrected
     regression test for that behaviour. Leave the tree's test files
     untouched.

## Constraints

- No network. Nothing to download.
- Do not read or modify `/opt/golden`, `/tests` or `/solution` — they are
  harness-owned.
- Do not commit, add remotes, fetch, or rewrite history in `/app/src`, and
  do not add or rename files inside the repository. The verifier expects the
  tree to differ from the pinned commit in **exactly one production file**,
  and that one file is where the bug lives. Your reproduction goes in
  `/app/reproduce.py`, outside the repository.
- Work only under `/app` and `/tmp`.

## What the verifier checks

1. Tree provenance: `/app/src` is still at the pinned parent commit with
   no history rewritten or objects fetched, and the only change in the
   tree is the minimal production fix.
2. Your reproduction is genuine: run against a pristine copy of the parent
   tree it must fail (non-zero); run against the repaired tree it must
   pass (zero). A script that always passes — or never — is not a
   reproduction.
3. The project's own regression test for this bug (the corrected, fix-era
   one, derived from upstream) passes against your repaired tree, and the
   four test modules above pass end to end.
4. Hidden cases: the same artifact-naming code path, exercised with declared
   versions and version strings the upstream regression test does not use.