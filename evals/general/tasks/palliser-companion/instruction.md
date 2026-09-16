# Elastic distortion crashes on bounding boxes that touch the canvas edge

## Situation

`/app/src` is a shallow, pinned clone of the `pytorch/vision` repository
(`https://github.com/pytorch/vision`), checked out at upstream commit
`8a5946ed6bce34bfeb26b964fc8875447d841ae8` and installed from that tree: a
Python 3.12 virtualenv at `/opt/venv` (on `PATH`) holds CPU builds of
`torch==2.14.0+cpu` and `torchvision==0.29.0+cpu`, and the
`torchvision.transforms.v2` implementation that Python imports is served from
the checked-out tree, so when you edit the checkout you edit the code Python
actually runs. The project's own test files live in the clone under `test/`.

There is **no network** at trial time: everything you need is already in the
image; `pip` and `git fetch` will not work.

## The bug

`torchvision.transforms.v2`'s elastic distortion (`ElasticTransform`, and the
`elastic_*` functional kernels: `elastic_bounding_boxes`, `elastic_keypoints`,
`elastic_mask`, ...) warps an input by sampling it through a displacement
field defined on an `(H, W)` grid. Bounding boxes are warped by transforming
their four corners through the same field.

When a bounding box **touches or crosses the canvas boundary** — for example a
box that spans the full canvas, `[0, 0, W, H]` in `XYXY` form — the elastic
kernel crashes instead of returning a warped box:

```
IndexError: index 76 is out of bounds for dimension 1 with size 76
```

with the numbers equal to the canvas width/height respectively. Boxes that are
fully inside the canvas (the top-left corner strictly inside and the size
strictly smaller than the canvas) work fine, which makes the behaviour look
arbitrary: a batch that happens to contain one full-size box fails while an
otherwise identical batch succeeds. The failure is independent of the box
format (`XYXY`, `XYWH`, `CXCYWH`, ...) and of the displacement values — even an
all-zero (identity) displacement crashes, because a corner of a full-size box
lands exactly on the last grid cell index, and the kernel looks the corner up
in the grid without guarding that index.

Users work around it by shrinking every box by a hair before warping, or by
catching the exception and re-running per box — neither is acceptable
behaviour for a library transform.

## What you need to do

1. **Write a failing reproduction first** — this is a deliverable. Create
   `/app/repro_elastic.py`: a plain, self-contained Python script that
   demonstrates the crash on the tree as it stands. It must import
   `torchvision` from the installed package (no path tricks, no arguments) and
   exit non-zero on the buggy tree, and — after the repair below — run to
   completion and exit 0, printing a one-line summary of the result. The
   verifier runs this exact script (`python3 /app/repro_elastic.py`) twice:
   once against a pristine copy of the pre-fix code, where it must fail, and
   once against your repaired tree, where it must succeed. A script that
   swallows the exception never passes both runs.

2. **Find and fix the bug** in the checked-out tree at `/app/src`, so that
   boxes touching or crossing the canvas boundary are warped like any other
   box: no exception, finite coordinates, and the box kept inside the canvas.
   Boxes fully inside the canvas must keep their exact current semantics.

3. **Keep the project's own elastic tests green.** The elastic-distortion
   tests live in `test/test_transforms_v2.py` in the class `TestElastic`; run
   them with the wrapper provided in the image:

   ```
   /app/run_pytest.sh test/test_transforms_v2.py::TestElastic -q
   ```

   At the pinned commit the whole class passes; keep it that way. The verdict
   on your fix is made by the verifier, which also runs the upstream
   regression tests for this behaviour and hidden cases of its own.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Repair the bug in place inside `/app/src`,
  changing only what the fix requires. Do not rewrite history, add remotes,
  fetch, or change build files. A repair that lives outside the checked-out
  tree (for example editing the installed package under `/opt/venv`) does not
  count and will be detected.
- The verifier asserts that the working tree remains at the pinned commit,
  that no files other than the minimal source file were modified or added
  (scratch files, `conftest.py` or other untracked files left in the checkout
  are rejected), and that no new files were added inside the `torchvision`
  package.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.

## What the verifier checks

1. The tree is still at commit `8a5946ed6bce34bfeb26b964fc8875447d841ae8`,
   no file other than the minimal source file was modified or added (untracked
   scratch files are rejected), the repair touches only the minimal source
   surface, and the code that runs under
   `torchvision.transforms.v2.functional` resolves to the checked-out tree.
2. Your reproduction: `/app/repro_elastic.py` exists and is a plain Python
   program that (a) fails against a pristine copy of the pre-fix code and
   (b) succeeds against your repaired tree.
3. The project's upstream regression tests for this behaviour (from the fix
   commit, extracted to `/opt/golden/` at image build time) pass.
4. The project's own existing `TestElastic` suite still passes.
5. Hidden cases pass over inputs the upstream test does not use: other box
   formats (`XYWH`, `CXCYWH`), near-boundary float coordinates in `float64`,
   a batch of edge-touching boxes under a non-trivial displacement field, and
   the `BoundingBoxes` wrapper path.

Deliverables: the repaired `/app/src` tree and the reproduction script
`/app/repro_elastic.py`.