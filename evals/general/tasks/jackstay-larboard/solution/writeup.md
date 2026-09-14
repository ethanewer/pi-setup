# Summary of the fix

## Symptom

`librosa.display.specshow` is used to draw 2D arrays of true/false values (for
example a mask of detected onsets, or a thresholded feature map). The image's
pixels look correct, but when a colourbar is attached to the returned
colour-mesh object, the colourbar spans the **entire continuous colour ramp**
with dozens of intermediate shades — even though the data has only two distinct
values. Binary data therefore appears as if it were analog, which is misleading
in figures and documentation.

## Root cause

When `specshow` is called without an explicit `cmap`, it infers a colormap from
the data. For boolean-dtype input the inference returns the boolean colormap
(black-and-white by default) — but nothing happened to the *normaliser*: the
image was still drawn with the default continuous `matplotlib.colors.Normalize`
scaled to the data range, so a colourbar drawn from the image interpolates
through every intermediate shade of the colormap.

## Fix

In the colormap-inference branch of `specshow` (the same place the diverging
colormap gets its `TwoSlopeNorm`), the code now also detects when the inferred
colormap is the boolean one **and** the input data really is boolean-dtype, and
in that case sets the normaliser to a `matplotlib.colors.BoundaryNorm` with
boundaries `[0, 0.5, 1]`. `BoundaryNorm` quantizes every value below 0.5 to the
first colour and every value above 0.5 to the last colour, so only the two
extreme levels of the colormap are ever used and the colourbar shows exactly
the two boolean levels. The normaliser is installed with `setdefault`, so a
normaliser the caller explicitly provides is never overwritten, and an
explicitly provided `cmap` bypasses the inference branch entirely so the
override case keeps its continuous behaviour.

## Verification

- `/app/repro.sh` plots boolean data and asserts the image's normaliser is a
  `BoundaryNorm` with boundaries `[0, 0.5, 1]`. It **fails against a pristine
  pre-fix copy of the package** (`LIBROSA_TREE=/opt/prefix`) and passes against
  the repaired tree.
- `python -m pytest tests/test_display.py -k "specshow or colorbar or
  infer_cmap" -o addopts="" --mpl
  --mpl-baseline-path=tests/baseline_images/test_display -p no:cacheprovider`
  — the project's own display tests stay green (including its pixel-exact
  pytest-mpl image comparisons).
- The upstream regression test for this bug (`test_specshow_boolean_norm`)
  passes, and with it the suite's own boolean rendering cases.