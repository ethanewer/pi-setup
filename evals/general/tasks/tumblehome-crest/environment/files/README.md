# Environment guide

This image contains a full checkout of the **mypy** type checker at
`/app/src`, checked out at a pinned upstream commit (the tree is the real
upstream code, with the `.git` history keeping only that one commit).

## What is installed

- Python 3.12.13 at `/usr/local/bin/python3` (also on `PATH`).
- The runtime dependencies mypy needs when run from the source checkout
  (`typing_extensions`, `mypy_extensions`, `pathspec`, `librt`,
  `ast-serialize`), and the project's own test runner: `pytest` plus
  `pytest-xdist` and `lxml`.
- `git` for exploring the checkout.

mypy itself is **not** pip-installed: `python3 -m mypy` from inside
`/app/src` runs the checked-out source, so edits you make to the tree are what
gets executed.

## How to check a file with the tree's mypy

```sh
cd /app/src
python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/mycache /path/to/file.py
```

Pass a cache directory under `/tmp`; the tree itself must stay clean.

## How to run the project's own tests (targeted only)

The full mypy test suite takes tens of minutes on this machine. Run targeted
subsets, e.g.:

```sh
cd /app/src
python3 -m pytest mypy/test/testcheck.py -k 'Narrowing or Narrow' -q
```

## Constraints

- There is **no network** in the trial container. Everything needed is
  already on disk.
- Do not modify anything under `/opt` (verifier-owned material) and do not
  modify anything outside `/app/src`.
- Keep the tracked working tree clean apart from purposeful source changes:
  no stray new files inside `/app/src` (scratch files belong in `/tmp` or in
  `/app`, outside the git tree).