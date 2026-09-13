#!/usr/bin/env python3
"""Exploratory probe for torchvision.ops.masks_to_boxes in the /app/src checkout.

Prints what masks_to_boxes returns for several masks.  A mask with no
foreground pixels (all zeros) should yield the degenerate box [0, 0, 0, 0] but
in this checkout crashes with a RuntimeError on the empty set of coordinates.
"""

import torch
from torchvision.ops import masks_to_boxes


def show(name, masks):
    try:
        out = masks_to_boxes(masks)
        print(f"{name}: OK -> {out.tolist()}")
    except RuntimeError as e:
        print(f"{name}: RuntimeError: {e}")


show("all-empty batch (3, 64, 64)", torch.zeros((3, 64, 64), dtype=torch.uint8))

m = torch.zeros((3, 10, 10), dtype=torch.uint8)
m[1, 2:5, 3:7] = 1
show("mixed empty/non-empty (3, 10, 10)", m)

show("single all-zero mask (1, 4, 4)", torch.zeros((1, 4, 4), dtype=torch.uint8))

s = torch.zeros((2, 6, 6))
s[0, 0, 5] = 1
s[1, 3:5, 1:3] = 1
show("foreground masks only (2, 6, 6)", s)