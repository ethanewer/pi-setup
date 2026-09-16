"""Hidden generalization case: a batch of edge-touching boxes under a
non-identity displacement field, plus the tv_tensors.BoundingBoxes dispatch
path (the API users actually call through ElasticTransform).

The upstream regression test uses a single full-canvas XYXY box with a random
displacement and only asserts "does not raise".  These cases exercise the same
kernel from a batch where every box touches a different canvas edge, under a
deterministic non-identity displacement, and through the dispatch wrapper
whose output is a tv_tensors.BoundingBoxes again.
"""

import torch
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F

H, W = 48, 52


def _displacement():
    # Deterministic non-identity displacement, small amplitude.
    gen = torch.Generator().manual_seed(1234)
    return (torch.rand((1, H, W, 2), generator=gen) - 0.5) * 0.4


def test_batch_of_edge_touching_boxes_nonidentity_displacement():
    boxes = torch.tensor(
        [
            [0.0, 0.0, float(W), float(H)],  # full canvas: every corner at the boundary
            [0.0, 2.0, float(W), 10.0],  # right edge touched
            [5.0, 0.0, 40.0, float(H)],  # bottom edge touched
            [0.0, 0.0, float(W), 20.0],  # left and right edges touched
            [3.0, 2.0, float(W), float(H)],  # right and bottom edges touched
        ]
    )
    displacement = _displacement()
    out = F.elastic_bounding_boxes(
        boxes, format=tv_tensors.BoundingBoxFormat.XYXY, canvas_size=(H, W), displacement=displacement
    )
    assert out.shape == boxes.shape, (out.shape, boxes.shape)
    assert torch.isfinite(out).all()
    x1, y1, x2, y2 = out[:, 0], out[:, 1], out[:, 2], out[:, 3]
    # the warped boxes stay valid and inside (or at) the canvas
    assert (x1 <= x2).all() and (y1 <= y2).all()
    assert (x2 <= W).all() and (y2 <= H).all()
    assert (x1 >= 0).all() and (y1 >= 0).all()


def test_interior_box_result_is_batch_independent():
    # An interior box must warp identically whether it is alone or in a batch
    # together with boundary-touching boxes.
    interior = torch.tensor([[6.0, 7.0, 20.0, 21.0]])
    batch = torch.tensor(
        [[6.0, 7.0, 20.0, 21.0], [0.0, 0.0, float(W), float(H)], [11.0, 3.0, float(W), 23.0]]
    )
    displacement = _displacement()
    alone = F.elastic_bounding_boxes(
        interior, format=tv_tensors.BoundingBoxFormat.XYXY, canvas_size=(H, W), displacement=displacement
    )
    together = F.elastic_bounding_boxes(
        batch, format=tv_tensors.BoundingBoxFormat.XYXY, canvas_size=(H, W), displacement=displacement
    )
    assert torch.allclose(alone[0], together[0], atol=1e-5)


def test_bboxes_wrapper_dispatch_full_canvas():
    # The ElasticTransform path dispatches through F.elastic on a
    # tv_tensors.BoundingBoxes; the full-canvas box must survive it and the
    # wrapper must preserve the tv_tensors type.
    tb = tv_tensors.BoundingBoxes(
        torch.tensor([[0.0, 0.0, float(W), float(H)]]),
        format=tv_tensors.BoundingBoxFormat.XYXY,
        canvas_size=(H, W),
    )
    displacement = torch.zeros((1, H, W, 2))
    out = F.elastic(tb, displacement=displacement)
    assert isinstance(out, tv_tensors.BoundingBoxes)
    vals = out.as_subclass(torch.Tensor)
    assert torch.isfinite(vals).all()
    assert torch.allclose(vals, torch.tensor([[0.0, 0.0, W - 1.0, H - 1.0]]), atol=1e-4), vals