#!/usr/bin/env python3
"""Hidden case 3: 3x2 grid, bands=3, alpha varying per pixel from 5 to 255.

A mix of heavily-overflowing pixels (alpha 5, 7, 9), a moderate one
(alpha 200) and a fully opaque one (alpha 255, where the operation must
be the identity). Every pixel in the grid is checked.
"""
import sys

import pyvips

GRID = [  # rows of (r, g, a)
    [[10, 20, 5], [200, 150, 9], [128, 128, 255]],
    [[254, 100, 200], [17, 34, 7], [255, 0, 60]],
]

def fixed_unpremultiply(value, alpha):
    if alpha <= 0:
        return 0
    scale = (256 * 255) // alpha
    return min((value * scale + 128) >> 8, 255)

height = len(GRID)
width = len(GRID[0])
bands = len(GRID[0][0])

# per-band 2D matrices, then bandjoin
band_images = []
for b in range(bands):
    mat = [[row[b] for row in rows] for rows in GRID]
    band_images.append(pyvips.Image.new_from_array(mat).cast("uchar"))
im = band_images[0].bandjoin(band_images[1:])
out = im.unpremultiply(uchar=True)

failures = 0
for y in range(height):
    for x in range(width):
        got = [int(round(v)) for v in out(x, y)]
        alpha = GRID[y][x][-1]
        exp_px = [fixed_unpremultiply(v, alpha) for v in GRID[y][x][:-1]] + [alpha]
        if got != exp_px:
            print(f"case3: pixel ({x},{y}): got {got}, expected {exp_px}")
            failures += 1

if failures:
    print("case3: FAIL", file=sys.stderr)
    sys.exit(1)
print("case3: PASS")
sys.exit(0)