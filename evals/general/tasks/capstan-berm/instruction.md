# capstan-berm

You are working inside a real upstream open-source library: **scikit-image**
(`scikit-image/scikit-image`), the image-processing toolkit, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug in
this tree's binary image thinning routine. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the bug
is part of the task.

## Environment

- Python 3.12 with numpy 2.1.3, scipy 1.14.1 and the project's build chain
  (meson, ninja, Cython 3.0.11, pythran 0.19.0) already installed, and the
  checked-out tree at `/app/src` installed **editable** (compiled extensions
  were built at image build time). `import skimage` works anywhere.
- Outbound network is not available and must not be relied on. Everything needed
  is baked in. Do not `pip install` anything.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`. Your fix lives in the working tree only.

## The bug (user-visible symptom)

The library exposes a function that thins a 2-D binary image down to its
skeleton: `skimage.morphology.thin`. In this tree, calling it on a
two-dimensional **boolean** image unexpectedly destroys the caller's array:
pixels are erased from the *input* array in place while the skeleton is being
computed, so any code that reuses its mask afterwards silently gets a corrupted
one. The function must leave the input untouched and return the skeleton in a
freshly allocated array.

Reproduce it with a couple of lines, e.g.:

```python
import numpy as np
from skimage.morphology import thin

img = np.zeros((10, 10), dtype=bool)
img[2:8, 2:8] = 1
orig = img.copy()
thin(img)
print("input_modified:", not np.array_equal(img, orig))   # prints True — bug
```

After a correct fix the same snippet must print `input_modified: False`. Note
the fingerprint of the bug: it only triggers for boolean input arrays (a
float/int input is copied while converting to bool, so it survives), and the
skeleton *returned* is correct either way — only the caller's array is
corrupted.

## Requirements

1. Fix the tree so that `thin` never modifies its input array, for **any**
   boolean input: dense, strided, non-contiguous, sliced, and with any
   `max_num_iter` value. The returned skeleton must be byte-for-byte identical
   to what the current (buggy) tree returns — the bug is purely that the input
   is clobbered, so a fix must not change the thinning algorithm itself.
2. Everything else must keep working exactly as before (the project's existing
   thinning/skeletonization tests all stay green).
3. The graded tree must be byte-identical to the original except for **the
   single source file where the bug lives**. Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (scratch `.py` in `/tmp` — not in
   `/app/src`).
2. **Localise**: the mutation happens while crunching the image into the
   internal thinning buffer. Grep the morphology sources for where the input
   gets converted to the internal byte buffer and where deletion decisions are
   written back. Find why a boolean input shares memory with that internal
   buffer, and make the buffer independent of the caller's array.
3. **Fix** with the smallest change that makes the repro print
   `input_modified: False`, then check nothing else changed: skeleton output on
   your repro must be identical before/after, and the project's own tests must
   stay green:
   ```bash
   cd /app/src && python -m pytest -p no:cacheprovider \
     skimage/morphology/tests/test_skeletonize.py
   ```
4. Stress the edges: boolean inputs that are views (`img[::2, ::2]`,
   `img[:, ::-1]`, `.T`), partial thinning (`thin(img, max_num_iter=k)`), and
   re-running on the same array — the input must be pristine after every call.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that every tracked
  file except the single source file the bug lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file fails);
- require `/app/summary.md` to exist;
- re-run the reproduction snippet and require `input_modified: False`;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, from a successor revision of the tree) into the
  test-suite directory, add further test modules with boolean inputs the
  upstream regression test does not use (a non-square mask, partial
  `max_num_iter` thinning, non-contiguous/strided/reversed boolean views that
  must be preserved including the buffer they alias), and run the project's own
  pytest on the whole set. Every test in every one of those modules must pass,
  including the regression test and the hidden cases.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.