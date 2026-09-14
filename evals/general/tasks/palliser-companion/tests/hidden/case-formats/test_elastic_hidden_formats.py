"""Hidden generalization case: canvas-boundary boxes in OTHER formats and
dtypes, not used by the upstream regression test.

The upstream test only covers an XYXY full-canvas box in float32.  These
cases push the same code path (elastic_bounding_boxes corner indexing) from
XYWH and CXCYWH formats, an all-zero (identity) displacement, and
near-boundary float64 coordinates whose ceil lands exactly on the canvas
size.  The expected values below are the outputs of the corrected kernel
with an identity displacement (the clamp maps a corner at index W/H to
W-1/H-1, so the warped full-canvas box becomes [0, 0, W-1, H-1] in XYXY).
"""

import torch
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F

H, W = 64, 76


def test_xywh_full_canvas_box():
    # XYWH full-canvas box: canonicalisation to XYXY yields [0, 0, W, H].
    box = torch.tensor([[0.0, 0.0, float(W), float(H)]])
    displacement = torch.zeros((1, H, W, 2))
    out = F.elastic_bounding_boxes(
        box, format=tv_tensors.BoundingBoxFormat.XYWH, canvas_size=(H, W), displacement=displacement
    )
    assert out.shape == box.shape
    assert torch.isfinite(out).all()
    # correct kernel maps the box to [0, 0, W-1, H-1] (in XYWH the sizes equal
    # the XYXY extents because the box starts at the origin)
    assert torch.allclose(out, torch.tensor([[0.0, 0.0, W - 1.0, H - 1.0]]), atol=1e-4), out


def test_cxcywh_full_canvas_box():
    # CXCYWH full-canvas box: cx = W/2, cy = H/2, size equal to the canvas.
    box = torch.tensor([[float(W) / 2, float(H) / 2, float(W), float(H)]])
    displacement = torch.zeros((1, H, W, 2))
    out = F.elastic_bounding_boxes(
        box, format=tv_tensors.BoundingBoxFormat.CXCYWH, canvas_size=(H, W), displacement=displacement
    )
    assert out.shape == box.shape
    assert torch.isfinite(out).all()
    # in CXCYWH the [0, 0, W-1, H-1] XYXY box is (cx=37.5, cy=31.5, w=75, h=63)
    expected = torch.tensor([[(W - 1.0) / 2, (H - 1.0) / 2, W - 1.0, H - 1.0]])
    assert torch.allclose(out, expected, atol=1e-4), out


def test_near_boundary_float64_xyxy():
    # Corners within 1px of the canvas edge ceil() up to exactly W/H, which is
    # the same out-of-range index the full-canvas box hits; float64 throughout.
    box = torch.tensor([[0.0, 0.0, W - 0.25, H - 0.25]], dtype=torch.float64)
    displacement = torch.zeros((1, H, W, 2), dtype=torch.float64)
    out = F.elastic_bounding_boxes(
        box, format=tv_tensors.BoundingBoxFormat.XYXY, canvas_size=(H, W), displacement=displacement
    )
    assert out.shape == box.shape
    assert out.dtype == torch.float64
    assert torch.isfinite(out).all()
    assert torch.allclose(out, torch.tensor([[0.0, 0.0, W - 1.0, H - 1.0]], dtype=torch.float64), atol=1e-4), out