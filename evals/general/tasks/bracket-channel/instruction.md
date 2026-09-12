# A corrupted-image bug in the libvips image library

This is a debugging task inside a real upstream codebase, in the SWE-bench
style: you are handed a genuine regression in a C library you did not write,
a failing behaviour, and a reproducer -- but not the file, the function, or
the line that is wrong. You must localise the defect in the real source
tree, repair it at its root, rebuild the library, and write a short
diagnosis.

## Environment

- `/app/src` is a working copy of the real **libvips** C image-processing
  library (`https://github.com/libvips/libvips`), checked out at a fixed
  upstream commit (shallow git repo, branch `baseline`). The tree is
  complete and editable and has working git metadata; you may commit if you
  like, but you do not have to.
- The tree has **already been built** with the project's own build system
  (meson + ninja) and **already installed** system-wide. The installed
  library is the build of this exact tree -- i.e. it contains the bug.
  `pyvips` (the Python binding) is installed and bound to that installed
  library, and `pytest` is available.
- There is **no network** in this container. You cannot fetch anything,
  re-clone, or `pip install` anything. Everything you need is in the image.
- Exactly **1 CPU** is available. The full build was done once at image
  creation; your rebuild only needs to recompile what you change.

## The failing behaviour

During conversion of a semi-transparent image, pixel values that scale past
the maximum during arithmetic are **not clamped**. Instead of saturating to
the brightest possible value (255 for 8-bit data), they **wrap around** and
come out dark and corrupted. The wrong result depends on the alpha channel,
so colours become visibly inconsistent between pixels, and the 8-bit output
silently differs from what the equivalent floating-point path produces.

Concretely: un-premultiplying the pixel value 20 with alpha 10 multiplies
by 255/10 = 25.5, giving 510 -- a value that cannot be stored in 8 bits.
The correct result is to clip to 255. The buggy build stores 254 instead
(510 wraps modulo 256).

Reproduce it with:

```bash
python3 /app/reproduce.py
```

While the bug is present it prints something like

```
unpremultiply([20, 10]) -> [254.0, 10.0]
BUG REPRODUCED: ...
```

and exits non-zero. After the library is fixed it prints

```
unpremultiply([20, 10]) -> [255.0, 10.0]
OK: value saturates at 255 as it should.
```

and exits 0.

## What to do

1. Observe the failing behaviour with `/app/reproduce.py`.
2. Localise the defect in the real source tree under `/app/src`. The
   operation involved is the one behind pyvips' `unpremultiply()`; search
   the C sources for the operation's implementation. Note that the
   corruption only appears in the 8-bit-to-8-bit path: conversion of
   floating-point images uses a different code path and is already correct.
   Keep your search targeted -- running or even reading the whole tree is
   not needed.
3. Fix the cause in the C source. Do **not** modify any test files, do
   **not** add Python-side post-processing or a wrapper that papers over the
   wrong output, and do **not** special-case particular input values. The
   root cause is one missing arithmetic step in one loop; repair it at its
   source so every pixel value that lands past the range saturates to the
   maximum and in-range values are untouched.
4. Rebuild and reinstall the changed library (only what changed recompiles):

   ```bash
   cd /app/src && ninja -C build install
   ldconfig || true     # may be a no-op depending on the uid you run as
   ```

   (`ldconfig` merely refreshes the loader cache; the installed library is
   picked up either way.) Then re-run `/app/reproduce.py` -- it must exit 0.
   Sanity-check with a second shape, e.g. an image with several pixels and
   different alpha values, to confirm saturating pixels and ordinary pixels
   both come out right.
5. Make sure the project's own relevant test still passes. libvips' test
   suite lives under `/app/src/test/test-suite/` (run from that directory):

   ```bash
   cd /app/src/test/test-suite && python3 -m pytest test_conversion.py::TestConversion -q
   ```

   This conversion test file must stay green after your change. (Note: the
   suite as it exists in this tree does **not** cover the wrapped-overflow
   case that `/app/reproduce.py` exercises -- that is exactly why the bug
   slipped through upstream -- so a green suite is necessary but not
   sufficient; `/app/reproduce.py` is your real regression check.)

## Deliverables

Both are checked.

1. **The repaired source tree in `/app/src`** -- your fix as ordinary edits
   in the C source, and the rebuilt, reinstalled library derived from it.
   The tree must otherwise remain exactly as checked out: do not change
   tests, documentation, build config, or other modules.
2. **`/app/diagnosis.md`** -- a short root-cause note (a few sentences, in
   your own words) stating:
   - **where** the defect lives (the module/directory in the C sources),
   - **the root cause**: what the code did wrong, why values past the
     maximum wrapped instead of saturating, and why only one data path was
     affected,
   - **the fix**: the minimal change you applied.

## Constraints

- Do not modify `/app/reproduce.py` or anything under `/tests` (you cannot
  see the verifier anyway).
- Do not remove, rename or replace the clone at `/app/src`; repair it in
  place.
- No network, 1 CPU: the rebuild must be incremental or it will not finish.