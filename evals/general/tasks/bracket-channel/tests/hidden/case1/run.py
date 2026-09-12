#!/usr/bin/env python3
"""Hidden case 1: 1x2 row, bands=2, tiny alpha (5) and zero alpha.

Both pixels run the uchar->uchar fast path. Pixel 0's un-premultiplied
value overflows 255 heavily (35 * 255/5 = 1785); the fixed library
saturates it to 255, a buggy library wraps it to 1785 % 256 = 249.
Pixel 1 (alpha 0) must come out as [0, 0] either way.
"""
import sys

import pyvips

EXPECTED = [[255, 5], [0, 0]]

def fixed_unpremultiply(value, alpha):
    """Independent expectation: the documented clamp semantics.

    scale = (256 * max_alpha) // alpha, max_alpha = 255 for 8-bit data,
    out = min((value * scale + 128) >> 8, 255)."""
    if alpha <= 0:
        return 0
    scale = (256 * 255) // alpha
    return min((value * scale + 128) >> 8, 255)

# 1x2 image, bands=2 (value, alpha). Built per band so values are exact.
v_band = pyvips.Image.new_from_array([[35, 200]]).cast("uchar")
a_band = pyvips.Image.new_from_array([[5, 0]]).cast("uchar")
im = v_band.bandjoin(a_band)
out = im.unpremultiply(uchar=True)

failures = 0
for x in range(2):
    got = [int(round(v)) for v in out(x, 0)]
    exp_px = [fixed_unpremultiply(35 if x == 0 else 200, 5 if x == 0 else 0),
              (5 if x == 0 else 0)]
    if got != exp_px or got != EXPECTED[x]:
        print(f"case1: pixel x={x}: got {got}, expected {exp_px}")
        failures += 1

if failures:
    print("case1: FAIL", file=sys.stderr)
    sys.exit(1)
print("case1: PASS")
sys.exit(0)