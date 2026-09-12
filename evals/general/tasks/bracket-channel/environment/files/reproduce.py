#!/usr/bin/env python3
"""Reproducer for a pixel-corruption bug in this libvips build.

The build is the upstream tree at the parent of the fix, so the bug is live.
Run it from anywhere:  python3 /app/reproduce.py
Exits 0 when the build behaves correctly, non-zero while the bug is present.
"""
import sys

import pyvips


def main():
    # A single semi-transparent pixel: value 20 with alpha 10 (about 4%
    # opacity). Unpremultiplying scales the value by 255/alpha, i.e. by 25.5:
    # 20 * 25.5 = 510, far past the 8-bit maximum of 255. Correct behaviour is
    # to SATURATE at 255 (the brightest value). The buggy build lets the value
    # wrap around modulo 256: 510 % 256 = 254, a dark, corrupted pixel.
    im = (pyvips.Image.black(1, 1, bands=2) + [20, 10]).cast("uchar")
    out = im.unpremultiply(uchar=True)(0, 0)

    print("unpremultiply([20, 10]) ->", out)
    if out != [255.0, 10.0]:
        print("BUG REPRODUCED: 510 was stored without saturation and wrapped "
              "to 254 instead of clipping to 255.", file=sys.stderr)
        return 1

    print("OK: value saturates at 255 as it should.")
    return 0


if __name__ == "__main__":
    sys.exit(main())