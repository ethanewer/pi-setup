#!/bin/bash
# Hidden case h2: the JPEG transform on an IMAGE BATCH whose leading
# dimensions are non-contiguous by STRIDED SLICING (every other sub-batch and
# every other frame kept), no transpose involved. The upstream regression test
# uses a transpose; this reaches the same kernel from a slicing-made layout,
# 2x5 frames, quality 50. Fails on the unfixed tree; must exit 0 with
# pixel-exact equality after a real fix.
set -u
cd /tmp || exit 1
/app/env/bin/python - <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
imgs = torch.randint(0, 256, (6, 4, 3, 16, 16), dtype=torch.uint8)[::2, ::2]  # (3,2,3,16,16)
assert not imgs.is_contiguous(), "input must be non-contiguous"
out = F.jpeg_image(imgs, quality=50)
ref = F.jpeg_image(imgs.contiguous(), quality=50)
assert out.shape == imgs.shape and out.dtype == imgs.dtype
assert torch.equal(out, ref)
assert not torch.equal(out, imgs), "output must be the re-encoded JPEG, not the input"
PY