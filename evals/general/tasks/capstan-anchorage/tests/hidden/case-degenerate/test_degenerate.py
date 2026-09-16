import torch
from torchvision.ops import masks_to_boxes


def test_fully_foreground_mask_with_empty_sibling():
    m = torch.zeros((2, 6, 5))
    m[0, :, :] = 1.0
    out = masks_to_boxes(m)
    assert torch.equal(out, torch.tensor([[0.0, 0.0, 4.0, 5.0], [0.0, 0.0, 0.0, 0.0]]))


def test_single_row_mask():
    m = torch.zeros((2, 3, 8))
    m[0, 1, :] = 1.0  # one full row -> y1 == y2
    m[1] = 0.0
    out = masks_to_boxes(m)
    assert torch.equal(out, torch.tensor([[0.0, 1.0, 7.0, 1.0], [0.0, 0.0, 0.0, 0.0]]))


def test_mixed_with_full_and_empty():
    m = torch.zeros((4, 9, 9))
    m[1, 2:6, 3:7] = 1.0
    m[3, :, :] = 1.0
    out = masks_to_boxes(m)
    assert torch.equal(
        out,
        torch.tensor(
            [
                [0.0, 0.0, 0.0, 0.0],
                [3.0, 2.0, 6.0, 5.0],
                [0.0, 0.0, 0.0, 0.0],
                [0.0, 0.0, 8.0, 8.0],
            ]
        ),
    )