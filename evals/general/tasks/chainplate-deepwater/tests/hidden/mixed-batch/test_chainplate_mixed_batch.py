"""Hidden case: batch of mixed odd/even integer boxes, all inside the canvas.

The upstream regression test converts a single box. This case converts a batch
in one call and asserts the full exact matrix as well as agreement with the
torchvision.ops reference, so partial fixes (correct first row only, clamped
rows, off-by-one rounding) cannot slip through.
"""
import torch
import torchvision.ops  # noqa: F401
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F


def _ref(cxcywh, dtype):
    return torchvision.ops.box_convert(cxcywh, in_fmt="cxcywh", out_fmt="xyxy").to(dtype)


def test_chainplate_mixed_batch_matches_ops_exactly():
    boxes = [[5, 6, 10, 13], [7, 9, 9, 7], [8, 8, 4, 3], [1, 1, 2, 2]]
    bb = tv_tensors.BoundingBoxes(
        boxes,
        format=tv_tensors.BoundingBoxFormat.CXCYWH,
        canvas_size=(17, 11),
        dtype=torch.int64,
    )
    out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)

    raw = bb.as_subclass(torch.Tensor)
    ref = _ref(raw, torch.int64)

    assert out.dtype == torch.int64
    assert (out.as_subclass(torch.Tensor) >= 0).all(), out.tolist()
    assert torch.equal(out.as_subclass(torch.Tensor), ref), (
        f"output {out.tolist()} diverges from ops reference {ref.tolist()}"
    )
    assert out.tolist() == [[0, 0, 10, 12], [2, 5, 11, 12], [6, 6, 10, 9], [0, 0, 2, 2]]