# strake-offing

You are working inside a real open-source codebase: **matplotlib**
(`matplotlib/matplotlib`), the Python plotting library, checked out at a
pinned commit in `/app/src` (working tree starts clean, library installed
editable from this tree). There is a bug in this tree's histogram machinery.
Your job is to find it, fix it in the working tree, and prove the fix with the
project's own test tooling. You are deliberately **not** told which file or
function to change: localising the bug is part of the task.

## Environment

- Python 3.12 with `python`/`python3`/`pip` on `PATH`. Installed and pinned:
  numpy 2.5.3, matplotlib's dependencies (contourpy, cycler, kiwisolver,
  fonttools, packaging, certifi, pillow, pyparsing 3.1.4), pytest 9.1.1, and
  the build toolchain (meson, meson-python, ninja, pybind11, setuptools-scm).
  `matplotlib` itself is installed **editable** from `/app/src` — editing the
  tree is enough, do **not** reinstall or upgrade anything.
- **There is no network** in this container. Do not try to fetch anything;
  everything the task needs is baked in.
- `cpus = 1`: one vCPU. Do not launch parallel builds or test jobs.
- Matplotlib uses the non-interactive `Agg` backend (`MPLBACKEND=Agg` is set,
  config dir `/tmp/mplconfig`).
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, merge, rebase or otherwise modify `.git`. Your fix must stay an
  uncommitted working-tree change.
- **Two importable copies of the library exist.** matplotlib is installed
  via a meson-python *editable wheel*, which registers an import hook (see
  `/usr/local/lib/python3.12/site-packages/_matplotlib_editable_loader.py`):
  a plain `import matplotlib` resolves to `/app/src` — your working tree. A
  second, pristine copy of the library **exactly as built at the pinned
  commit** (importable, byte-complete, read-only) lives at `/opt/prefix`.
  Because the editable hook hijacks imports, the `/opt/prefix` copy is loaded
  in a subprocess by setting `MESONPY_EDITABLE_SKIP=/app/src/build/cp312` and
  `PYTHONPATH=/opt/prefix/lib` (the hook honours that skip variable and then
  falls back to a normal `sys.path` search). This is tooling detail, not the
  bug — the verifier runs your reproduction in both configurations (below).

## The bug (user-visible symptom)

Users feed **durations** — elapsed-time values — into matplotlib's histogram
feature. Two everyday shapes exist for such data, and both are affected:

- a numpy array of time deltas, e.g. `np.array([1, 2, 5, 7], dtype="timedelta64[D]")`
  (whole-day durations, but the same crash occurs for seconds, milliseconds,
  microseconds, … units);
- a Python list of `datetime.timedelta` objects, e.g.
  `[datetime.timedelta(seconds=0), datetime.timedelta(seconds=1), …]`.

Instead of failing cleanly, the histogram call dies deep inside the numeric
library: numpy tries to group the durations into bins by comparing them with
floating-point bin edges, and refuses, surfacing an internal error such as

```
TypeError: ufunc 'less' did not contain a loop with signature matching types
(<class 'numpy.dtypes.TimeDelta64DType'>, <class 'numpy.dtypes._PyFloatDType'>)
```

(For Python `timedelta` objects the failure is a different, equally unhelpful
`TypeError: '<' not supported between instances of 'datetime.timedelta' and
'float'`.) Either way the caller gets a message that says nothing about *what*
went wrong or *what to do instead*.

The contract you must restore: **duration input to the histogram feature is
not supported at all, so the call must fail immediately and clearly** — a
`TypeError` whose message says the histogram does not currently support
timedelta inputs and tells the caller to convert the durations to plain
numbers first. The project's own regression test for this bug requires the
message to contain the phrase `does not currently support timedelta inputs`.
Ordinary numeric data must be completely unaffected: the histogram must keep
binning floats, ints and numeric arrays exactly as before.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — an executable script (`#!/bin/bash` or any
   interpreter) that demonstrates the symptom. Its contract:

   - It must honour the environment variable `MPL_TREE` naming the copy of
     matplotlib to test, defaulting to `/app/src` when unset. The verifier
     calls the script twice:
     * `MPL_TREE=/app/src /app/repro.sh` — your repaired working tree (the
       editable hook already resolves imports there), and
     * `MPL_TREE=/opt/prefix MESONPY_EDITABLE_SKIP=/app/src/build/cp312
       PYTHONPATH=/opt/prefix/lib /app/repro.sh` — the pristine pre-fix copy
       (the skip variable and `PYTHONPATH` are already set for you; rely on
       them, do not unset them).
     So the script must genuinely exercise the library code it imports — no
     hardcoding results based on the variable's value.
   - It feeds **both** duration shapes (a numpy `timedelta64` array and a
     list of `datetime.timedelta` objects) to the histogram feature and
     demands the clean, explanatory `TypeError` (message containing
     `does not currently support timedelta inputs`) in each case. Any opaque
     crash, any other exception type, or a call that succeeds at all scores a
     failure for that case.
   - It also runs one numeric sanity check (bins a small float array and
     verifies the returned counts are right).
   - It prints a short diagnosis line to stdout and nothing else; it exits
     `0` if and only if every check above passes, and nonzero (printing why)
     otherwise. It must work no matter what the current working directory is
     when invoked, and must not touch anything outside `/tmp`.
   - You may split the script across files (e.g. a small Python helper next to
     it under `/app`), but `/app/repro.sh` must remain the entry point.

   On the **unfixed** tree this script must fail: the pristine pre-fix copy at
   `/opt/prefix` dies with the opaque errors above, so your script exits
   nonzero there. Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that `/app/repro.sh`
   passes (exit 0): duration input — numpy `timedelta64` values and Python
   `datetime.timedelta` values, in any unit, shape or position — must raise
   the clean `TypeError` described above before anything else happens, and
   every non-duration input must keep working byte-for-byte as before. Fix the
   mechanism, not one input: the same defect is reachable with any `timedelta64`
   unit, with two- or multi-dataset histogram calls where *any* dataset is a
   duration, and with list/array forms; do not special-case your
   reproduction's array size in a wrapper.

3. **Break nothing else.** The histogram feature must remain exactly as it
   was for floats, ints, fixed bin counts and ranges, stacked/histtype styles,
   empty inputs, NaN data, etc. A useful self-check that runs a green slice of
   the project's own `test_axes.py` hist tests (all offline; note that some
   image-comparison hist tests in this development tree are red for unrelated
   reasons — this exact selection is green):

   ```
   cd /app/src
   python3 -m pytest \
     lib/matplotlib/tests/test_axes.py::test_hist_float16 \
     lib/matplotlib/tests/test_axes.py::test_hist_unequal_bins_density \
     lib/matplotlib/tests/test_axes.py::test_hist_single_color_multiple_datasets \
     lib/matplotlib/tests/test_axes.py::test_hist2d_density \
     lib/matplotlib/tests/test_axes.py::test_hist2d_autolimits \
     lib/matplotlib/tests/test_axes.py::test_hist_step_geometry \
     lib/matplotlib/tests/test_axes.py::test_hist_step_bottom_geometry \
     lib/matplotlib/tests/test_axes.py::test_hist_stacked_step_geometry \
     lib/matplotlib/tests/test_axes.py::test_hist_stacked_step_bottom_geometry \
     lib/matplotlib/tests/test_axes.py::test_hist_barstacked_bottom_unchanged \
     lib/matplotlib/tests/test_axes.py::test_hist_emptydata \
     lib/matplotlib/tests/test_axes.py::test_hist_unused_labels \
     lib/matplotlib/tests/test_axes.py::test_hist_labels \
     lib/matplotlib/tests/test_axes.py::test_length_one_hist \
     lib/matplotlib/tests/test_axes.py::test_numerical_hist_label \
     lib/matplotlib/tests/test_axes.py::test_unicode_hist_label \
     lib/matplotlib/tests/test_axes.py::test_hist_auto_bins \
     lib/matplotlib/tests/test_axes.py::test_hist_nan_data \
     lib/matplotlib/tests/test_axes.py::test_hist_range_and_density \
     lib/matplotlib/tests/test_axes.py::test_hist_with_empty_input \
     lib/matplotlib/tests/test_axes.py::test_hist_zorder \
     -q -p no:cacheprovider
   ```

   All 25 collection nodes must pass.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; do not touch `tests/`, `pyproject.toml`,
   `meson.build`, or any other metadata; if you create scratch files to
   investigate, delete them before you finish; make no commits; leave
   `/usr/local/lib/python3.12/site-packages` completely untouched (do not
   install, uninstall, or drop files into it). The grader compares every
   file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail. (`/app/repro.sh`, any helper you put next to it,
   and `/app/summary.md` live outside `/app/src` and are fine.)

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the installed library (scratch files in `/tmp`). Run
   `MPL_TREE=/app/src /app/repro.sh`; watch it fail on the unfixed tree. Then
   verify the pre-fix direction too:
   `MPL_TREE=/opt/prefix MESONPY_EDITABLE_SKIP=/app/src/build/cp312
   PYTHONPATH=/opt/prefix/lib bash /app/repro.sh` must also fail. Reading the
   `_matplotlib_editable_loader.py` hook (in site-packages) explains why the
   extra variables are needed for the `/opt/prefix` direction.
2. **Localise** the bug by reading the code: find the histogram function,
   trace what happens to the input from the moment it arrives until the
   numeric library is asked to bin it, and understand where a clear
   "unsupported input" error could — and should — be raised first.
3. **Fix** with the smallest possible change in that one source file, and
   confirm `/app/repro.sh` passes with `MPL_TREE=/app/src`. Note for your
   own diagnostics: after you edit a source file the editable hook picks up
   the new bytes on the *next* process — just re-run.
4. **Prove nothing else broke** with the pytest command in item 3 above.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above
   (executable; it must pass on the fixed tree and fail on the pre-fix copy).
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert the trust anchors baked into the image (the golden test bytes and
  the pristine pre-fix package are sha256-pinned; site-packages was
  snapshot-pinned at image build time and must be byte-identical now);
- assert that `HEAD` is still the pinned commit, that the tree contains
  exactly one commit, and that every tracked file except the single source
  file the bug lives in is byte-identical to that commit (any other
  modification, added file or untracked scratch file fails; likewise any
  change under site-packages);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and be
  executable as specified;
- run your `/app/repro.sh` against your repaired tree (it must exit 0) and
  against the pristine pre-fix copy at `/opt/prefix` (it must exit
  nonzero) — unless your reproduction genuinely targets the symptom it
  cannot pass both directions;
- independently re-check both directions (repaired tree must raise the clean
  `TypeError` for both duration shapes; the pre-fix copy must still crash with
  an opaque message that does *not* contain the clean phrase);
- plant the project's **own regression test** for this bug (upstream added it
  with the fix; it is baked into the image at `/opt/golden` with a hash pin)
  and run it against your repaired tree — it must pass — and at the same time
  run it against the pristine pre-fix copy — it must fail;
- run the 25-test slice above — all must stay green;
- run hidden cases on your tree covering `timedelta64` units and shapes the
  upstream test does not use, Python `timedelta` with histogram parameters,
  multi-dataset calls with a duration among them, numeric-data unaffected,
  and non-duration histogram errors keeping their own error messages (a
  `TypeError` raised for a numeric histogram call must not be relabelled as
  the timedelta error). Reward is binary: 1 if and only if everything above
  passes, otherwise 0.

Do not look up or fetch the fix from anywhere online or from git history —
there is no network, and the fix commit is not in this clone. Find it in the
code.