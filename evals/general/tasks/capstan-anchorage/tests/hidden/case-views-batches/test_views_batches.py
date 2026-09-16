import torch
from torchvision.ops import masks_to_boxes


def test_sliced_noncontiguous_views():
    base = torch.zeros((6, 12, 12))
    base[0, 4:6, 1:3] = 1.0
    m = base[::2]  # views of rows 0, 2, 4 of base; only the first is non-empty
    out = masks_to_boxes(m)
    assert torch.equal(
        out,
        torch.tensor(
            [[1.0, 4.0, 2.0, 5.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
        ),
    )


def test_stride_slice_with_empty_head():
    base = torch.zeros((5, 7, 7))
    base[2, :, 0] = 1.0
    m = base[::2]  # masks 0, 2, 4 of base; only base row 2 (mask 1) is non-empty
    out = masks_to_boxes(m)
    assert torch.equal(
        out,
        torch.tensor(
            [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 6.0], [0.0, 0.0, 0.0, 0.0]]
        ),
    )


def test_larger_mixed_batch():
    m = torch.zeros((16, 24, 24))
    expected = torch.zeros((16, 4))
    for i in range(0, 16, 3):
        m[i, 5:9, 7:13] = 1.0
        expected[i] = torch.tensor([7.0, 5.0, 12.0, 8.0])
    out = masks_to_boxes(m)
    assert torch.equal(out, expected)