#!/usr/bin/env python3
"""Hidden case 3: draw_flood with an explicit test image (square frame).

The upstream regression test never passes the optional `test` image, so the
fill always runs against the image itself. Here a white square frame with a
black inner hole acts as the flood mask via `equal=True` (flood while the
test pixel equals the start pixel's test colour): from a start on the frame,
the fill must paint exactly the frame pixels of the (separate) image with
the ink value and must stop at the hole and at the outer edge. The expected
painted set is computed in pure Python from exact integer rectangle
geometry. An out-of-bounds start on the same setup must raise.
"""
import sys

import pyvips

S = 100
INK = 90
OUT = (15, 15, 70, 70)    # outer filled rectangle: x in [15,85), y in [15,85)
INNER = (35, 35, 30, 30)  # inner black hole:       x in [35,65), y in [35,65)
START = (80, 50)          # on the frame, not on any boundary
failures = 0


def on_frame(x, y):
    ox, oy, ow, oh = OUT
    ix, iy, iw, ih = INNER
    in_outer = ox <= x < ox + ow and oy <= y < oy + oh
    in_hole = ix <= x < ix + iw and iy <= y < iy + ih
    return in_outer and not in_hole


# mask: white frame with a black hole
test = pyvips.Image.black(S, S)
test = test.draw_rect(255, OUT[0], OUT[1], OUT[2], OUT[3], fill=True)
test = test.draw_rect(0, INNER[0], INNER[1], INNER[2], INNER[3], fill=True)

im = pyvips.Image.black(S, S)

# out-of-bounds start with the test image bound must be rejected
try:
    im.draw_flood(INK, 300, 300, test=test, equal=True)
    print("case3: FAIL: out-of-bounds start with test image did not raise")
    failures += 1
except pyvips.error.Error as e:
    print(f"case3: ok: out-of-bounds start with test image rejected: {e}")

# valid start on the frame: the fill must stop at the hole and the edge
out = im.draw_flood(INK, START[0], START[1], test=test, equal=True)
vals = bytes(out.write_to_memory())

mism = 0
for y in range(S):
    for x in range(S):
        got = int(vals[y * S + x])
        want = INK if on_frame(x, y) else 0
        if got != want:
            mism += 1
            if mism <= 8:
                print(f"case3: pixel ({x},{y}) got {got}, expected {want}")

if mism:
    print(f"case3: FAIL: {mism} frame pixels wrong (of {S*S})")
    failures += 1
else:
    print("case3: ok: frame flood painted exactly the frame on all pixels")

if failures:
    print("case3: FAIL", file=sys.stderr)
    sys.exit(1)
print("case3: PASS")
sys.exit(0)