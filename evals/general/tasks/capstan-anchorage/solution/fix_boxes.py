#!/usr/bin/env python3
"""Apply the upstream empty-mask guard to torchvision/ops/boxes.py

masks_to_boxes() runs ``torch.where(mask != 0)`` per mask and then assigns
``torch.min(x)``/``torch.max(x)`` (and the y counterparts) unconditionally.
For a mask with no foreground pixels, x and y are empty tensors and the
reduction raises::

    RuntimeError: min(): Expected reduction dim to be specified for
    input.numel() == 0. Specify the reduction dim with the 'dim' argument.

The fix guards the four assignments with ``if x.numel() > 0:`` so an
all-zero mask keeps the pre-initialised degenerate box [0, 0, 0, 0].  This is
exactly the change upstream shipped for this bug.  Idempotent: exits 0 when
the fix is already present, exits 1 if the expected buggy snippet is not
found (the file has drifted).
"""

import sys
from pathlib import Path

BUGGY_BLOCK = [
    "    for index, mask in enumerate(masks):\n",
    "        y, x = torch.where(mask != 0)\n",
    "\n",
    "        bounding_boxes[index, 0] = torch.min(x)\n",
    "        bounding_boxes[index, 1] = torch.min(y)\n",
    "        bounding_boxes[index, 2] = torch.max(x)\n",
    "        bounding_boxes[index, 3] = torch.max(y)\n",
]

FIXED_BLOCK = [
    "    for index, mask in enumerate(masks):\n",
    "        y, x = torch.where(mask != 0)\n",
    "\n",
    "        if x.numel() > 0:\n",
    "            bounding_boxes[index, 0] = torch.min(x)\n",
    "            bounding_boxes[index, 1] = torch.min(y)\n",
    "            bounding_boxes[index, 2] = torch.max(x)\n",
    "            bounding_boxes[index, 3] = torch.max(y)\n",
]


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <path-to-boxes.py>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    text = path.read_text()
    lines = text.splitlines(keepends=True)

    if any("if x.numel() > 0:" in line for line in lines):
        # Guard already present; make sure it guards the min/max assignments.
        joined = "".join(lines)
        if "if x.numel() > 0:\n            bounding_boxes[index, 0]" in joined:
            print(f"{path}: fix already applied, leaving unchanged")
            return 0
        print(f"{path}: unexpected content (guard present but not wired up)", file=sys.stderr)
        return 1

    n = len(BUGGY_BLOCK)
    for i in range(len(lines) - n + 1):
        if lines[i : i + n] == BUGGY_BLOCK:
            lines[i : i + n] = FIXED_BLOCK
            path.write_text("".join(lines))
            print(f"{path}: applied empty-mask guard at line {i + 1}")
            return 0

    print(f"{path}: buggy snippet not found; file has drifted", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))