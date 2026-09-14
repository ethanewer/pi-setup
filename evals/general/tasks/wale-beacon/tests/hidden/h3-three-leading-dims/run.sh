#!/bin/bash
# Hidden case h3: the JPEG transform on a SIX-dimensional batch with THREE
# leading dimensions whose memory layout is scrambled by transpose(0,2), the
# last three dims still (3, H, W). The upstream regression test uses a 5-D
# input with one transpose on two leading dims; this exercises a different
# leading layout and quality 25. Fails on the unfixed tree; must exit 0 with
# pixel-exact equality after a real fix.
set -u
cd /tmp || exit 1
/app/env/bin/python - <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
x = torch.randint(0, 256, (2, 3, 4, 3, 16, 16), dtype=torch.uint8).transpose(0, 2)  # (4,3,2,3,16,16)
assert not x.is_contiguous(), "input must be non-contiguous"
out = F.jpeg_image(x, quality=25)
ref = F.jpeg_image(x.contiguous(), quality=25)
assert out.shape == x.shape and out.dtype == x.dtype
assert torch.equal(out, ref)
assert not torch.equal(out, x), "output must be the re-encoded JPEG, not the input"
PY