# jackstay-larboard

You are working inside a real open-source codebase: **librosa**
(`librosa/librosa`), the Python audio and music-signal-analysis library,
checked out at a pinned commit in `/app/src` (the working tree starts clean,
with the library installed from this tree in editable mode). There is a bug in
this tree's plotting/drawing machinery. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the bug
is part of the task.

## Environment

- Python 3.12 with `python`/`python3`/`pip` on `PATH`. Installed and pinned:
  numpy 2.5.3, scipy 1.18.1, numba 0.67.0, scikit-learn 1.9.1, matplotlib
  3.11.1, pytest 9.1.1, pytest-mpl 0.19.0, pytest-cov 7.1.0, plus all of
  librosa's own dependencies (soundfile, pooch, soxr, lazy_loader, msgpack,
  joblib, decorator). `librosa` itself is installed **editable** from
  `/app/src` — editing the tree is enough, do **not** reinstall or upgrade
  anything.
- **There is no network** in this container. Do not try to fetch anything;
  everything the task needs is baked in.
- `cpus = 1`: one vCPU. Do not launch parallel builds or test jobs.
- Matplotlib uses the non-interactive `Agg` backend (`MPLBACKEND=Agg` is set).
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, merge, rebase or otherwise modify `.git`. Your fix must stay an
  uncommitted working-tree change.
- `/opt/prefix/librosa` is a pristine read-only copy of this package **as it
  is at the pinned commit** — the verifier uses it to double-check your
  reproduction (see Grading). Leave it alone.

## The bug (user-visible symptom)

Users frequently draw binary masks with librosa's spectrogram-style heatmap
function: a 2D array whose entries are true/false — for example "onset
detected here", "below threshold here", or any boolean feature map — passed
straight to the display function. The coloured image itself looks correct: the
dark cells and the bright cells are in the right places.

But when a colour bar is added to the figure, it is wrong. Instead of showing
the two levels the data actually have — false on one end, true on the other —
the colour bar spans the entire continuous colour ramp and shows dozens of
intermediate shades that can never occur in the data. Figures and documentation
built from boolean data therefore look as though the underlying quantity were
analog and graded, which silently misleads readers. The picture is fine; the
scale tells a lie. The affected behaviour is the colour normalisation used when
the display function infers the colour map for boolean input: binary data must
be drawn (and its colour bar must run) over exactly two levels, with no shaded
gradient between them.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — an executable script (`#!/bin/bash` or any
   interpreter) that demonstrates the symptom. Its contract:

   - It must honour an environment variable `LIBROSA_TREE` naming a directory
     whose `librosa` package should be imported (the script should prepend
     that directory to the Python import path), defaulting to `/app/src` when
     the variable is unset. The verifier runs the script once with
     `LIBROSA_TREE=/app/src` (your fixed tree) and once with
     `LIBROSA_TREE=/opt/prefix` (the pristine pre-fix package), so the script
     must genuinely exercise the library code it imports — no hardcoding
     results based on the variable's value.
   - It plots a 2D boolean array with the heatmap function described above,
     then inspects the returned image object's colour *normaliser* (in
     matplotlib terms the normaliser is the object that maps data values to
     colours: a `matplotlib.colors.Normalize` instance is continuous, a
     `matplotlib.colors.BoundaryNorm` with boundaries `[0, 0.5, 1]` produces
     exactly two levels).
   - It prints a short diagnosis line to stdout and nothing else; it exits
     `0` if and only if the boolean colour bar is correct (a two-level
     boundary normaliser with boundaries `[0, 0.5, 1]` is attached), and
     exits nonzero (printing why) otherwise.
   - It must work no matter what the current working directory is when it is
     invoked, and must not touch anything outside `/tmp`.

   On the **unfixed** tree this script must fail: the boolean plot currently
   attaches a plain continuous `Normalize`, so your script exits nonzero.
   Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0) — for boolean-dtype input, the display
   function must attach the two-level boundary normaliser so the colour bar
   shows exactly the two boolean levels. Fix the mechanism, not one input:
   the same defect is reachable with boolean arrays of any shape, size or
   sparsity, and only for genuinely boolean data; two-valued *float* arrays
   must keep their continuous behaviour, and a caller who passes an explicit
   colour map or their own normaliser must keep exactly what they asked for
   (see Grading). Do not special-case your reproduction's array size in a
   wrapper.

3. **Break nothing else.** Everything else must keep working exactly as
   before: continuous, diverging and `vscale`-normalised plots; colour bars;
   automatic colour-map inference. The project's existing tests must stay
   green. A useful check that runs the project's own display tests (all
   offline, pixel-exact image comparisons included):

   ```
   cd /app/src
   python3 -m pytest tests/test_display.py -k "specshow or colorbar or infer_cmap" \
       -o addopts="" --mpl --mpl-baseline-path=tests/baseline_images/test_display \
       -p no:cacheprovider
   ```

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; do not touch `tests/`, `setup.cfg`,
   `pyproject.toml`, or any other metadata; if you create scratch files to
   investigate, delete them before you finish; make no commits. The grader
   compares every file's bytes against the pinned commit's own blobs, so
   cosmetic side-changes also fail. (`/app/repro.sh` and `/app/summary.md`
   live outside `/app/src` and are fine.)

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the installed library (scratch files in `/tmp`). Set
   `LIBROSA_TREE=/app/src` and run your `/app/repro.sh`; watch it fail on the
   unfixed tree. Then verify the pre-fix direction too:
   `LIBROSA_TREE=/opt/prefix bash /app/repro.sh` must also fail (the pristine
   package has the same bug).
2. **Localise** the bug by reading the code: find the display function, read
   how it *infers* a colour map when the caller gives none, and how the
   normaliser that the returned image object carries is (or is not) set up
   for each inferred colour-map family. Understand why boolean input currently
   falls through to the default continuous normaliser.
3. **Fix** with the smallest possible change in that one source file, and
   confirm `/app/repro.sh` passes with `LIBROSA_TREE=/app/src`.
4. **Prove nothing else broke** with the pytest command in item 3 above.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above
   (executable; it must pass on the fixed tree and fail on the pre-fix one).
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned commit and the fix commit is
  unreachable from this clone, and that every tracked file except the single
  source file the bug lives in is byte-identical to that commit (any other
  modification, added file or untracked scratch file fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and be
  executable as specified;
- run your `/app/repro.sh` against your repaired tree (it must exit 0) and
  against the pristine pre-fix package at `/opt/prefix` (it must exit
  nonzero) — unless your reproduction genuinely targets the symptom it
  cannot pass both directions;
- independently re-check the normaliser on both trees (fixed tree must carry
  the two-level `BoundaryNorm` with boundaries `[0, 0.5, 1]`; the pre-fix
  package must still carry a plain continuous `Normalize`);
- plant the project's **own regression test** for this bug (upstream added it
  with the fix; it is baked into the image at `/opt/golden` with a hash pin)
  and run it against your tree — it must pass, together with the baseline
  image that accompanies it;
- run a targeted slice of the project's existing `test_display` suite (the
  `specshow`/`colorbar`/`infer_cmap` tests, pixel-exact image comparisons
  included) — all must stay green;
- run hidden cases on your tree: boolean arrays of other shapes and
  sparsities must show exactly two levels; two-valued *float* arrays must
  NOT get the boundary normaliser; an explicit caller colour map or
  normaliser must be honoured untouched. Reward is binary: 1 if and only if
  everything above passes, otherwise 0.

Do not look up or fetch the fix from anywhere online or from git history —
there is no network, and the fix commit is not in this clone. Find it in the
code.