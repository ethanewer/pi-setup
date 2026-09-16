# chainplate-deepwater

You are working inside a real open-source codebase: **PyTorch Vision**
(`pytorch/vision`), the computer-vision library that ships with PyTorch,
checked out at a pinned commit in `/app/src` (the working tree starts clean).
There is a bug in this tree's bounding-box conversion code. Your job is to
find it, fix it in the working tree, and prove the fix with the project's own
test suite.

## Environment

- `/app/src` is a shallow (one commit), detached clone of the upstream
  repository. It is the real code that shipped at the pinned commit, bug
  included. **There is no network** in this container, and the repository
  history contains exactly one commit, so nothing can be looked up or fetched:
  the work happens in the tree that is here.
- `/app/env` is a Python virtual environment with the pinned dependencies
  `torch==2.10.0+cpu` and `torchvision==0.25.0+cpu` (plus `pytest`), installed
  from the PyTorch CPU wheel index at image-build time. The installed
  `torchvision` package's `transforms/v2` and `tv_tensors` Python modules were
  then replaced with the exact bytes of this checkout, so the package you
  import runs **precisely the code in `/app/src`** — the released wheel's
  module bytes are gone. This means the venv package is not a reference
  implementation: it carries the same bug, and it will not start behaving
  correctly until you fix the tree and refresh the package mirror
  (see `/app/README-TESTING.md`, which documents the one-command refresh and
  the exact pytest invocations that work offline).
- `cpus = 1`: one vCPU. Numeric thread pools are already pinned to 1.
- Working python and pytest everywhere: `/app/env/bin/python` and
  `/app/env/bin/python -m pytest`.
- Scratch files belong in `/tmp`, not inside `/app/src`.

Read `/app/README-TESTING.md` first — it explains the code-mirror setup, how to
reproduce, and how to run the project's own tests offline.

## The bug (user-visible symptom)

Converting an **integer-typed** bounding box from center/width/height form
(`CXCYWH`) to the corner form (`XYXY`) can produce a box whose top or left
edge is **negative**, even when the box lies entirely inside the image. The
triggers are simple and easy to trip on: any box with an *odd* width or height.
The same conversion on floating-point boxes is correct, and so is the
independent reference implementation in `torchvision.ops` — so the discrepancy
is only visible to code that keeps boxes in an integer dtype, which is a
common real-world choice for annotation data.

Concretely, this box is fully inside a `17 x 11` image:

```python
import torch
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F

bb = tv_tensors.BoundingBoxes(
    [[5, 6, 10, 13]],
    format=tv_tensors.BoundingBoxFormat.CXCYWH,
    canvas_size=(17, 11),
    dtype=torch.int64,
)
out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)
print(out)
```

Its center is `(5, 6)` with width 10 and height 13, so the true corner box is
`(0, -0.5, 10, 12.5)`, which truncates to `(0, 0, 10, 12)` for integer
output. Instead the current tree emits `(0, -1, 10, 12)`: the top edge has
strayed one pixel above the image. The reproduction is a single command:

```bash
/app/env/bin/python /opt/repro.py
```

It prints the offending box and then fails its assertions. A correct tree
prints `OK`. (Aside: `/opt/repro.py` exists on disk exactly so you do not have
to retype the snippet above.)

The interesting property is **which** corner values are right. The conversion
must agree with the project's own reference conversion,
`torchvision.ops.box_convert(..., in_fmt="cxcywh", out_fmt="xyxy")`,
computed on the same input, element for element. Think carefully about what
"truncating a half" means — a fix that merely clamps negative values to zero
will *not* match the reference on boxes that sit off-canvas, and the hidden
verification exercises exactly that distinction.

## What you must do

1. **Reproduce.** Run `/app/env/bin/python /opt/repro.py` and observe the
   negative corner.
2. **Localise.** Find where the integer conversion goes wrong. The tree is
   real and large; the conversion code is where you would expect it to be for
   a transforms library this size. Compare the integer path against the
   floating-point path and against the `torchvision.ops` reference — the
   divergence tells you exactly which rounding decision is wrong.
3. **Fix** the tree in `/app/src` the way the upstream project would: minimal,
   in the genuine source location, preserving the public API, the out-of-place
   *and* in-place behaviour, and the input dtype of the result. Then refresh
   the installed package (one `cp`, see `/app/README-TESTING.md`) so
   `/app/env` runs your fixed code.
4. **Prove it.** The upstream regression test for this bug ships in the image
   at `/opt/golden/test_transforms_v2.py` — it is the project's own
   `test/test_transforms_v2.py` from the fixed revision. Per
   `/app/README-TESTING.md`, plant it over the checked-out copy and run:
   - the regression test itself
     (`-k test_cxcywh_to_xyxy_odd_dimensions`), and
   - the whole `TestConvertBoundingBoxFormat` class, which is the project's
     own surrounding suite for this code and checks every conversion against
     the `torchvision.ops` reference.
   Both must pass. Your fix must also keep the original reproduction printing
   `OK`.

## Deliverables and the exact state the verifier checks

The verifier scores **binary** (1 or 0) and asserts all of the following:

1. **`/app/src`** — the repaired tree. Its `HEAD` must still be the pinned
   commit, and the working tree must differ from that commit in **exactly one
   tracked source file**: the one your fix needs. Every other tracked file
   must be byte-identical to the pinned commit (the verifier re-hashes actual
   file bytes, not git status), and there must be **no untracked, non-ignored
   files** — so any test file you planted or scratch file you created inside
   `/app/src` must be removed (or moved to `/tmp`) before you finish.
2. **`/app/summary.md`** — a short change summary: where the bug was (module
   and function), what the wrong rounding did, how you changed it, and the
   verification you ran (the reproducer, the regression test, and the class
   run, with their results).
3. **`/app/env`** — the installed package refreshed so it runs your fixed
   code (the mirror must match the tree).

The instruction deliberately does not tell you which file to change: finding
it is part of the task. Do not commit, fetch, or rewrite history in
`/app/src`. Do not modify `/opt` (the golden test and reproducer are read-only
inputs). Everything you need is already in the image — the container has no
network, and that is permanent.