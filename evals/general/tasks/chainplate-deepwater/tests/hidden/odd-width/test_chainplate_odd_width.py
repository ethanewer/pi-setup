"""Hidden case: odd-width integer box, truncation-vs-clamping discrimination.

The upstream regression test uses an odd height (13) with an even width (10).
This case uses an odd WIDTH and, critically, a box that genuinely pokes one
pixel above the canvas: a fix that merely clamps negatives to zero would be
WRONG here, because integer conversion truncates toward zero and must agree
with torchvision.ops.box_convert element for element.
"""
import torch
import torchvision.ops  # noqa: F401  (registers box_convert)
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F


def _ref(cxcywh, dtype):
    return torchvision.ops.box_convert(cxcywh, in_fmt="cxcywh", out_fmt="xyxy").to(dtype)


def test_chainplate_odd_width_int64_truncates_like_ops():
    bb = tv_tensors.BoundingBoxes(
        [[5, 5, 11, 12], [3, 3, 5, 5]],
        format=tv_tensors.BoundingBoxFormat.CXCYWH,
        canvas_size=(10, 10),
        dtype=torch.int64,
    )
    out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)

    raw = bb.as_subclass(torch.Tensor)
    ref = _ref(raw, torch.int64)

    assert out.dtype == torch.int64
    assert torch.equal(out.as_subclass(torch.Tensor), ref), (
        f"output {out.tolist()} diverges from ops reference {ref.tolist()}"
    )
    # Exact expected values, computed by truncating (cx - w/2) toward zero:
    #  row 0: trunc(5 - 5.5) = 0  (this box legitimately has trunc(5 - 6) = -1
    #         on the y axis, so (out >= 0).all() is intentionally FALSE here)
    #  row 1: trunc(3 - 2.5) = 0, trunc(5.5) = 5
    assert out.tolist() == [[0, -1, 10, 11], [0, 0, 5, 5]], out.tolist()