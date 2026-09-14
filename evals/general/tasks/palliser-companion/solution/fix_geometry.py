#!/usr/bin/env python3
"""Apply the upstream fix for the elastic-bounding-box canvas-boundary crash.

torchvision/transforms/v2/functional/_geometry.py::elastic_bounding_boxes
indexes the inverse displacement grid with the ceil()ed long coordinates of
each box corner.  A corner that reaches the canvas edge (x2 == W or y2 == H)
produces an index of exactly W/H and the grid lookup raises::

    IndexError: index 76 is out of bounds for dimension 1 with size 76

The fix clamps the two index tensors to the grid bounds before the lookup,
which is exactly the change upstream shipped for this bug.  Idempotent:
exits 0 when the fix is already present, exits 1 if the expected buggy
anchor is not found (the file has drifted).
"""

import sys
from pathlib import Path

TARGET = Path("/app/src/torchvision/transforms/v2/functional/_geometry.py")

ANCHOR = (
    "    index_x, index_y = index_xy[:, 0], index_xy[:, 1]\n"
    "\n"
    "    # Transform points:\n"
)
INSERT = (
    "    index_x, index_y = index_xy[:, 0], index_xy[:, 1]\n"
    "    index_x = index_x.clamp(0, inv_grid.shape[2] - 1)\n"
    "    index_y = index_y.clamp(0, inv_grid.shape[1] - 1)\n"
    "\n"
    "    # Transform points:\n"
)


def main() -> int:
    text = TARGET.read_text()
    if INSERT in text:
        print(f"{TARGET}: fix already present")
        return 0
    if ANCHOR not in text:
        print(f"FAIL: anchor line not found in {TARGET}", file=sys.stderr)
        return 1
    text = text.replace(ANCHOR, INSERT, 1)
    TARGET.write_text(text)
    print(f"{TARGET}: patched")
    return 0


if __name__ == "__main__":
    sys.exit(main())