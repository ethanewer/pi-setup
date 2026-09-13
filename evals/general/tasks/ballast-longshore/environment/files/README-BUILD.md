# ballast-longshore — build notes

This image was built for a debugging task. Read `instruction.md` first.

## What is installed

- A shallow, pinned clone of `https://github.com/matplotlib/matplotlib` at
  commit `91d115ec161286b70da1447f53844b909247741f` (detached HEAD) in
  `/app/src`. Only that one commit exists in the local object store.
- That checkout, installed in editable mode (`pip install --no-build-isolation
  -e .`). `import matplotlib` resolves to `/app/src/lib/matplotlib`; editing
  `.py` files under `/app/src/lib` is immediately live, no rebuild needed.
- The C extensions (and the vendored freetype / harfbuzz / qhull libraries)
  were compiled at image build time. On first `import` after you edit sources,
  the meson editable loader runs a fast incremental check; it can be slow the
  very first time but not afterwards.
- Python 3.12.13 with pinned `numpy==2.5.3`, `pytest==8.4.2`,
  `pyparsing==3.1.4` and friends.

## Constraints at trial time

- **No network.** `git fetch`, `curl`, `pip install`, `apt-get` all fail.
- Single CPU for your work; the numeric thread-count env vars are already
  pinned to 1.
- `MPLBACKEND=Agg` is set; use `matplotlib.use('Agg')` in scripts for good
  measure.

## Running the project's tests

From the repository root:

```
cd /app/src
python3 -m pytest lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_use_offset -q
```

Only run targeted node ids: whole test modules contain slow, flaky
image-comparison tests.

## Deliverables

- The fixed repository at `/app/src`.
- A short root-cause note at `/app/explanation.md` (see `instruction.md`).