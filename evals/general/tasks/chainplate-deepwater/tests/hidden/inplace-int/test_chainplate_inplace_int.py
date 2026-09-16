"""Hidden case: inplace conversion of integer boxes.

The upstream regression test converts out-of-place only. The fix deliberately
changed the in-place path (integer results are computed in float and written
back truncated into the input), so this case drives inplace=True on a
tv_tensors.BoundingBoxes AND on a pure int64 tensor, for an odd-height box.
"""
import torch
import torchvision.ops  # noqa: F401
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F


def _ref(cxcywh, dtype):
    return torchvision.ops.box_convert(cxcywh, in_fmt="cxcywh", out_fmt="xyxy").to(dtype)


def test_chainplate_inplace_bboxes_updates_input_and_matches_ops():
    bb = tv_tensors.BoundingBoxes(
        [[5, 6, 10, 13]],
        format=tv_tensors.BoundingBoxFormat.CXCYWH,
        canvas_size=(17, 11),
        dtype=torch.int64,
    )
    ref = _ref(torch.tensor([[5, 6, 10, 13]], dtype=torch.int64), torch.int64)

    out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY, inplace=True)

    assert out.dtype == torch.int64
    # The input tensor must now hold the converted corners, truncated like ops.
    assert torch.equal(bb.as_subclass(torch.Tensor), ref), f"input not updated: {bb.tolist()}"
    assert torch.equal(out.as_subclass(torch.Tensor), ref), out.tolist()
    assert out.tolist() == [[0, 0, 10, 12]]

    # Out-of-place and in-place must agree.
    bb2 = tv_tensors.BoundingBoxes(
        [[5, 6, 10, 13]],
        format=tv_tensors.BoundingBoxFormat.CXCYWH,
        canvas_size=(17, 11),
        dtype=torch.int64,
    )
    oop = F.convert_bounding_box_format(bb2, new_format=tv_tensors.BoundingBoxFormat.XYXY)
    assert torch.equal(oop.as_subclass(torch.Tensor), out.as_subclass(torch.Tensor))


def test_chainplate_inplace_pure_tensor():
    raw = torch.tensor([[5, 6, 10, 13]], dtype=torch.int64)
    ref = _ref(raw, torch.int64)

    out = F.convert_bounding_box_format(
        raw, old_format=tv_tensors.BoundingBoxFormat.CXCYWH,
        new_format=tv_tensors.BoundingBoxFormat.XYXY, inplace=True,
    )

    assert out.dtype == torch.int64
    assert torch.equal(out, ref), f"{out.tolist()} != {ref.tolist()}"
    assert out.tolist() == [[0, 0, 10, 12]]