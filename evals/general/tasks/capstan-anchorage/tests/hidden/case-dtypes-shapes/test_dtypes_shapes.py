import torch
from torchvision.ops import masks_to_boxes


def test_bool_all_empty_batch():
    m = torch.zeros((3, 5, 5), dtype=torch.bool)
    out = masks_to_boxes(m)
    assert out.shape == (3, 4)
    assert out.dtype == torch.float
    assert torch.equal(out, torch.zeros((3, 4), dtype=torch.float))


def test_float64_mixed_empty_and_nonempty():
    m = torch.zeros((2, 8, 8), dtype=torch.float64)
    m[1, 1:3, 2:4] = 1.0
    out = masks_to_boxes(m)
    assert out.dtype == torch.float
    assert torch.equal(out, torch.tensor([[0.0, 0.0, 0.0, 0.0], [2.0, 1.0, 3.0, 2.0]]))


def test_float32_single_pixel_and_empty():
    m = torch.zeros((2, 4, 4))
    m[0, 2, 1] = 1.0  # single foreground pixel at row 2, col 1
    m[1] = 0.0
    out = masks_to_boxes(m)
    assert torch.equal(out, torch.tensor([[1.0, 2.0, 1.0, 2.0], [0.0, 0.0, 0.0, 0.0]]))