# Masks with no foreground pixels must not crash box extraction

## Situation

`/app/src` is a shallow, pinned clone of the `pytorch/vision` repository
(`https://github.com/pytorch/vision`), checked out at upstream commit
`df421b423f714eb3ae22cab2b0e6e7a6f6bb29be` and installed from that tree: a
Python 3.12 virtualenv at `/opt/venv` (on `PATH`) holds CPU builds of
`torch==2.10.0+cpu` and `torchvision==0.25.0+cpu`, and the `torchvision.ops`
implementation that Python imports is served from the checked-out tree, so
when you edit the checkout you edit the code Python actually runs. The
project's own test files and fixtures are in the clone under `test/`.

There is **no network** at trial time: everything you need is already in the
image; `pip` and `git fetch` will not work.

## The bug

`torchvision.ops.masks_to_boxes(masks)` turns a batch of segmentation masks
`(N, H, W)` into an `(N, 4)` tensor of bounding boxes in `(x1, y1, x2, y2)`
format, one box per mask. When **a mask contains no foreground pixels at all**
(all entries zero), the function does not return a degenerate box: it tries to
take the minimum and maximum of an empty set of pixel coordinates and raises

```
RuntimeError: min(): Expected reduction dim to be specified for input.numel() == 0. Specify the reduction dim with the 'dim' argument.
```

so any user whose batch contains at least one fully-background mask gets an
exception instead of boxes, and people work around it by special-casing empty
masks by hand. A mask with foreground pixels must keep its exact current
semantics: the tight box around all non-zero pixels.

## Reproducing the failure

```
python3 /app/probe_masks_to_boxes.py
```

prints the result for several masks. An all-zero batch crashes with the
`RuntimeError` above where it should print `[[0, 0, 0, 0], ...]`; a batch
mixing one empty and one non-empty mask crashes on the empty one.

A one-liner that shows the same thing:

```
python3 -c "import torch; from torchvision.ops import masks_to_boxes; print(masks_to_boxes(torch.zeros((3, 64, 64))))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a mask with no
foreground pixels yields the degenerate box `[0, 0, 0, 0]` (and the batch
continues normally), **without changing the result for any mask that does have
foreground pixels**.

Drive your work with the project's own test runner and the project's own
tests. The masks-to-boxes tests live in `test/test_ops.py` in the class
`TestMasksToBoxes`; run them with the wrapper provided in the image:

```
/app/run_pytest.sh test/test_ops.py::TestMasksToBoxes -q
```

At the pinned commit the existing test in that class is green; keep it that
way. The verdict on your fix is made by the verifier, which also runs the
upstream regression tests for this behaviour and checks hidden cases its own
way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier asserts that the working tree remains at the pinned commit,
  that no other tracked files were modified, and that no new files were added
  inside the `torchvision` package. A repair that lives outside the checked-out
  tree (e.g. editing the installed package under `/opt/venv` instead of the
  tree) does not count.

## What the verifier checks

1. The tree is still at commit `df421b423f714eb3ae22cab2b0e6e7a6f6bb29be`, no
   extra tracked files were changed, the repair touches only the minimal
   source surface, and the code that runs under `torchvision.ops` resolves to
   the checked-out tree.
2. The project's upstream regression tests for this behaviour (from the fix
   commit, extracted to `/opt/golden/` at image build time) pass.
3. The project's own existing masks-to-boxes tests still pass.
4. Hidden cases pass over inputs the upstream test does not use: other mask
   dtypes (`bool`, `float64`), single-pixel foreground masks,
   non-contiguous/sliced mask views, degenerate single-column masks, and
   fully-foreground masks.

Deliverable: the repaired `/app/src` tree.