#!/usr/bin/env python3
"""Hidden case 2: far / exact-boundary offsets and a full fill on 32x32.

The upstream regression test only uses a 100x100 image with offsets 200 and
-1 and a single ink. Here a 32x32 image is flooded with the scalar-ink
draw_flood using an offset 1000 rows past the image, an exact-boundary
offset (x == width), and an offset 1000 below the image; all must be
rejected. A valid start at (0, 0) must fill the whole 32x32 uniform region
with the ink value -- an all-1024-pixels expectation computed directly.
"""
import sys

import pyvips

W = 32
INK = 200
failures = 0

im = pyvips.Image.black(W, W)

for name, x, y in (("far right (x=1000)", 1000, 17),
                   ("exact width (x=32)", W, 0),
                   ("far below (y=1000)", 5, 1000)):
    try:
        im.draw_flood(INK, x, y)
        print(f"case2: FAIL: draw_flood at ({x}, {y}) ({name}) did not raise")
        failures += 1
    except pyvips.error.Error as e:
        print(f"case2: ok: draw_flood at ({x}, {y}) ({name}) rejected: {e}")

out = im.draw_flood(INK, 0, 0)
vals = bytes(out.write_to_memory())
n_ink = sum(1 for v in vals if int(v) == INK)
if n_ink != W * W:
    print(f"case2: FAIL: full-region flood painted {n_ink}/{W*W} pixels")
    failures += 1
else:
    print(f"case2: ok: full-region flood painted all {W*W} pixels")

if failures:
    print("case2: FAIL", file=sys.stderr)
    sys.exit(1)
print("case2: PASS")
sys.exit(0)