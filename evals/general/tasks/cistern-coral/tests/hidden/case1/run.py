#!/usr/bin/env python3
"""Hidden case 1: boundary rejection and a valid corner flood on 640x480.

The upstream regression test only uses a 100x100 image with starts at 200
and -1. Here the image is 640x480 and the starts sit exactly on the right
edge (x == width), exactly on the bottom edge (y == height), and one pixel
past the corner (x == width, y == height): all must be rejected with an
error, while the last in-bounds pixel (639, 479) must still flood and paint
the connected region with the ink value.
"""
import sys

import pyvips

W, H = 640, 480
INK = 222
failures = 0

im = pyvips.Image.black(W, H)

# out-of-bounds starts at the exact boundaries and past the corner
for name, x, y in (("x == width", W, H // 2),
                   ("y == height", W // 2, H),
                   ("past the corner", W, H)):
    try:
        im.draw_flood(INK, x, y)
        print(f"case1: FAIL: draw_flood at ({x}, {y}) ({name}) did not raise")
        failures += 1
    except pyvips.error.Error:
        print(f"case1: ok: ({x}, {y}) ({name}) rejected")

# a valid start at the last in-bounds pixel must still paint everything
out = im.draw_flood(INK, W - 1, H - 1)
vals = bytes(out.write_to_memory())

if int(vals[(H - 1) * W + (W - 1)]) != INK:
    print(f"case1: FAIL: valid start at (W-1, H-1) did not paint: "
          f"corner={int(vals[(H-1)*W + (W-1)])}, expected {INK}")
    failures += 1
else:
    print("case1: ok: valid start at (W-1, H-1) paints the connected region")

# the uniform black region must be filled entirely (interior pixel too)
if int(vals[(H // 2) * W + (W // 2)]) != INK:
    print(f"case1: FAIL: flood did not reach the interior: "
          f"{int(vals[(H//2)*W + (W//2)])}, expected {INK}")
    failures += 1
else:
    print("case1: ok: flood reached the interior")

if failures:
    print("case1: FAIL", file=sys.stderr)
    sys.exit(1)
print("case1: PASS")
sys.exit(0)