#!/bin/bash
# Hidden case h1: the JPEG transform on a TRANSPOSED VIDEO batch, via the
# jpeg_video kernel (the upstream regression test only exercises jpeg_image on
# a transposed image batch). Different leading layout, different frame count,
# different quality. Fails on the unfixed tree (stride RuntimeError); must
# exit 0 with pixel-exact equality after a real fix.
set -u
cd /tmp || exit 1
/app/env/bin/python - <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
video = torch.randint(0, 256, (2, 5, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)  # (5,2,3,16,16)
assert not video.is_contiguous(), "input must be non-contiguous"
out = F.jpeg_video(video, quality=90)
ref = F.jpeg_video(video.contiguous(), quality=90)
assert out.shape == video.shape and out.dtype == video.dtype
assert torch.equal(out, ref)
assert not torch.equal(out, video), "output must be the re-encoded JPEG, not the input"
PY