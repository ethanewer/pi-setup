# wale-beacon

You are working inside the real open-source tree of **PyTorch's torchvision**
library (`pytorch/vision`), checked out at a pinned historical commit in
`/app/src` (clean working tree, detached HEAD). There is a bug in this tree's
image-compression transform. Your job is to find it, fix it in the working
tree, and prove the fix with your own reproduction plus the project's own
tests. You are deliberately **not** told which file or function to change or
what exactly to change: localising the bug is part of the task.

## Environment

- `/app/src` is the repository, checked out at the pinned commit. It is
  writable, but **do not commit, fetch, push, rebase, stash, or otherwise
  modify `.git`** — the tree must stay detached at the pinned commit.
- The Python environment is the venv at `/app/env` (`/app/env/bin/python`),
  with the official CPU wheels `torch==2.14.0+cpu` and
  `torchvision==0.29.0+cpu` plus `pytest`. The **pure-Python transform logic
  of the installed `torchvision` package resolves to the working tree at
  `/app/src`** (the compiled image codec, e.g. the JPEG encoder/decoder,
  comes from the wheel). So a change you make in the tree is the change that
  runs when you import `torchvision`.
- **Run your scripts from `/app` or `/tmp`, never with a working directory
  inside `/app/src`:** the source tree's own `torchvision/` package is
  incomplete (it lacks the compiled extensions) and shadows the installed
  wheel, so imports fail with `operator torchvision::nms does not exist`.
- There is **no network** in this container. Everything you need is baked in.
- `cpus = 1`; numeric thread pools are pinned to 1. If you run pytest, use
  `python -m pytest` from outside `/app/src`.
- The project's own tests live in `/app/src/test/`. They are plain pytest
  (the venv already has everything they need) and use only synthetic data.

## The bug (user-visible symptom)

The JPEG re-compression transform —
`torchvision.transforms.v2.functional.jpeg`, and its per-input kernels
`jpeg_image` (for images, and for pure tensors with a leading batch
dimension) and `jpeg_video` (for videos) — takes a tensor whose last three
dimensions are `(channel, height, width)` and any number of leading
batch/frame dimensions. It re-encodes every frame to JPEG and decodes it
back, and returns a tensor of the same shape and dtype.

Users have reported that this transform **crashes with an internal
tensor-layout error the moment the input batch is not memory-contiguous**,
which happens trivially: for example a video tensor of shape
`(frames, 2, 3, H, W)` whose two leading dimensions have been swapped with
`.transpose(0, 1)`, or a stack of images sliced with a step. The failure is
raised before any pixel work happens, and looks like:

```
RuntimeError: view size is not compatible with input tensor's size and stride (at least one dimension spans across two contiguous subspaces). Use .reshape(...) instead.
```

Contiguous tensors of exactly the same shape and values work fine and
produce correct output — the same data succeeds once you call
`.contiguous()` on it, and fails without. (The full history: this affects
both `jpeg_image` and `jpeg_video`, on CPU, in this tree.)

The affected behaviour in one sentence: **the JPEG transform must accept any
input whose last three dimensions are `(C, H, W)`, regardless of the memory
layout of the leading dimensions, and produce exactly the same output pixels
as it would for the contiguous copy of the same data.**

## Your job

1. **Reproduce it first — before you change any code.** Write
   `/app/repro.py`, your own minimal reproduction of the symptom. Its
   contract:

   - It is an executable Python script with shebang `#!/app/env/bin/python`
     that can be run as `/app/repro.py` from any working directory.
   - It constructs its own synthetic `uint8` input with `C = 3` (colours)
     and non-empty `H, W` (e.g. 16×16), arranged so the **leading**
     dimensions are non-contiguous — the way the symptom describes (a
     `transpose`/`permute` of a batch or video tensor, or a strided slice),
     while the last three dimensions stay `(3, H, W)`.
   - It asserts its input is not contiguous; otherwise it exits non-zero
     with a message.
   - It runs the affected JPEG transform (via
     `torchvision.transforms.v2.functional`) on that non-contiguous input
     AND on the same data made contiguous (`input.contiguous()`), with the
     same quality, and asserts both results have the same shape, the same
     dtype, and identical elements.
   - It prints the input shape and a short result line, and exits **0 if and
     only if** every check above passed; on the unfixed tree it exits
     non-zero (letting the raised exception propagate is fine — the error
     shown above is exactly what a user sees).
   - It must not write anything into `/app/src`.

   Confirm the script fails on this tree *now*, before fixing anything.

2. **Localise the bug.** Read the tree, find where the transform turns the
   non-contiguous input into a failure, and understand *why* contiguous
   inputs of the same shape succeed.

3. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.py` passes (exit 0). Fix the mechanism, not one input: the
   same defect is reachable with videos and images, with any number of
   leading dimensions, and with several ways of making the layout
   non-contiguous (see Grading).

4. **Break nothing else.** The project's own JPEG tests must stay green.
   They are in `/app/src/test/test_transforms_v2.py` under `TestJPEG`
   (run from `/tmp`, e.g. `cd /tmp && /app/env/bin/python -m pytest
   "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-5]"
   ...`). These tests use continuous contiguous inputs and exercise the
   exact same code path.

5. **Write `/app/summary.md`** — a short write-up: what the bug was, what
   you changed, and how you verified the fix.

## Grading

The verifier (the container's own `/tests`) will, on your final container:

- assert that `HEAD` is still the pinned parent commit and that the upstream
  fix commit is **not** reachable from this clone;
- require every tracked file to be byte-identical to the pinned commit
  except the single source file where the bug lives (any other change or
  stray file fails);
- require `/app/repro.py` (executable) and `/app/summary.md` (non-empty)
  and run your reproduction **twice**: against a pristine copy of the
  buggy module baked into the image (it must fail — proving the symptom is
  real and your reproduction targets it) and against your repaired tree (it
  must pass);
- run the project's **own regression test** for this bug (extracted from the
  upstream fix commit at image build time and baked into the image), which
  must pass on your repaired tree and fail on the pristine buggy module;
- run the project's existing `TestJPEG` tests (listed above) and require
  them to pass, proving the fix broke nothing else;
- run authored hidden cases that exercise the same code path from inputs the
  upstream test does not use (a transposed video, a strided-slice batch, a
  three-leading-dimension transpose), each of which must pass on your tree
  and fail on the pristine buggy module.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.py` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.