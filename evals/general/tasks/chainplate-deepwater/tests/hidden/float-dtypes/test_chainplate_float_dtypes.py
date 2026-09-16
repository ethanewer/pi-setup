"""Hidden case: floating-point and non-default integer dtypes.

The upstream regression test covers int64 only. This case pins down that
float32 boxes keep exact floating semantics (never truncated, unchanged by the
fix), and that int16/int32 boxes follow the same truncation-on-final-cast
semantics as int64, preserving their dtype on output.
"""
import torch
import torchvision.ops  # noqa: F401
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F


def _ref(cxcywh, dtype):
    return torchvision.ops.box_convert(cxcywh, in_fmt="cxcywh", out_fmt="xyxy").to(dtype)


def test_chainplate_float32_conversion_is_exact_and_untouched():
    bb = tv_tensors.BoundingBoxes(
        [[5, 6, 10, 13]],
        format=tv_tensors.BoundingBoxFormat.CXCYWH,
        canvas_size=(17, 11),
        dtype=torch.float32,
    )
    out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)

    raw = bb.as_subclass(torch.Tensor)
    ref = torchvision.ops.box_convert(raw, in_fmt="cxcywh", out_fmt="xyxy")

    assert out.dtype == torch.float32
    assert torch.equal(out.as_subclass(torch.Tensor), ref), f"{out.tolist()} != {ref.tolist()}"
    # The floating path must keep real halves: (6 - 6.5) = -0.5 on the y axis,
    # while the even width halves exactly: (5 - 5) = 0.
    assert out.tolist() == [[0.0, -0.5, 10.0, 12.5]]


def test_chainplate_int16_and_int32_odd_dims_truncate_like_ops():
    for dtype in (torch.int16, torch.int32):
        bb = tv_tensors.BoundingBoxes(
            [[7, 9, 9, 7], [5, 6, 10, 13]],
            format=tv_tensors.BoundingBoxFormat.CXCYWH,
            canvas_size=(17, 11),
            dtype=dtype,
        )
        out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)

        raw = bb.as_subclass(torch.Tensor)
        ref = _ref(raw, dtype)

        assert out.dtype == dtype, out.dtype
        assert torch.equal(out.as_subclass(torch.Tensor), ref), (
            f"[{dtype}] {out.tolist()} diverges from ops reference {ref.tolist()}"
        )
        assert (out.as_subclass(torch.Tensor) >= 0).all(), out.tolist()
        assert out.tolist() == [[2, 5, 11, 12], [0, 0, 10, 12]]