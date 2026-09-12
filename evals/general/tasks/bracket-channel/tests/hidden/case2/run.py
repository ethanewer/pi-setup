#!/usr/bin/env python3
"""Hidden case 2: 1x2 row, bands=4 (RGBA-shaped), alpha 10 and 200.

Pixel 0 overflows (11 * 25.5 = 280.5); pixel 1's first band overflows
moderately (254 * 255/200 ~ 323) while its other bands stay in range and
must be untouched by the clamp. Verifies saturation AND that in-range
values are unchanged.
"""
import sys

import pyvips

PIXELS = [[11, 20, 30, 10],   # value,value,value,alpha
          [254, 128, 64, 200]]

def fixed_unpremultiply(value, alpha):
    if alpha <= 0:
        return 0
    scale = (256 * 255) // alpha
    return min((value * scale + 128) >> 8, 255)

# per-band 1x2 arrays, then bandjoin to bands=4
bands = []
for b in range(4):
    bands.append(pyvips.Image.new_from_array([[p[b] for p in PIXELS]]).cast("uchar"))
im = bands[0].bandjoin(bands[1:])
out = im.unpremultiply(uchar=True)

failures = 0
for x in range(2):
    got = [int(round(v)) for v in out(x, 0)]
    exp_px = [fixed_unpremultiply(p, PIXELS[x][3]) for p in PIXELS[x][:-1]] + [PIXELS[x][3]]
    if got != exp_px:
        print(f"case2: pixel x={x}: got {got}, expected {exp_px}")
        failures += 1

if failures:
    print("case2: FAIL", file=sys.stderr)
    sys.exit(1)
print("case2: PASS")
sys.exit(0)