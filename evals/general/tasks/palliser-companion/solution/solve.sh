#!/bin/bash
# Oracle for palliser-companion: applies the canvas-boundary clamp to the
# torchvision/transforms/v2/functional/_geometry.py checkout (/app/src),
# writes the reproduction deliverable /app/repro_elastic.py, verifies it
# passes on the repaired tree, and runs the upstream regression tests
# extracted into /opt/golden/ at image build time plus the project's own
# TestElastic suite.
set -e

python3 /solution/fix_geometry.py /app/src/torchvision/transforms/v2/functional/_geometry.py

echo "== write the reproduction deliverable =="
cat > /app/repro_elastic.py <<'PYEOF'
#!/usr/bin/env python3
"""Reproduction for the elastic-distortion canvas-boundary crash.

A bounding box that spans the full canvas makes the elastic kernel look up
corner coordinates at an out-of-range grid index.  On a fixed tree this
runs to completion and prints the warped box.
"""
import sys

import torch
import torchvision
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F

H, W = 64, 76
bbox = torch.tensor([[0.0, 0.0, float(W), float(H)]])  # box exactly covering the canvas
displacement = torch.zeros((1, H, W, 2))               # identity warp

out = F.elastic_bounding_boxes(
    bbox,
    format=tv_tensors.BoundingBoxFormat.XYXY,
    canvas_size=(H, W),
    displacement=displacement,
)

assert out.shape == bbox.shape, (out.shape, bbox.shape)
assert torch.isfinite(out).all()
print("elastic_bounding_boxes full-canvas box OK:", out.tolist())
PYEOF
chmod +x /app/repro_elastic.py

echo "== reproduction on the repaired tree =="
python3 /app/repro_elastic.py

echo "== upstream regression tests (from /opt/golden) =="
/app/run_pytest.sh \
  /opt/golden/test_transforms_v2.py::TestElastic::test_kernel_bounding_boxes_at_canvas_boundary \
  -q

echo "== project's own existing elastic-distortion suite =="
/app/run_pytest.sh test/test_transforms_v2.py::TestElastic -q