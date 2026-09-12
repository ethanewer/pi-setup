#!/usr/bin/env python3
"""Reproducer: pyvips' draw_flood silently accepts an out-of-image start point.

Run it from anywhere:  python3 /app/reproduce.py
Exits 0 once the library is fixed, non-zero while the bug is present.

The library in this image is the upstream tree at the parent of the fix, so
the bug is live. A flood-fill whose start point lies past the right or
bottom edge of the image is accepted silently: the call returns, nothing is
drawn, and the caller gets no signal that the coordinates were invalid.
"""
import sys

import pyvips


def main():
    failures = 0

    # 1) Out-of-bounds start points must be rejected with an explicit error.
    im = pyvips.Image.black(100, 100)
    for name, x, y in (("x past the right edge (x=200, y=50)", 200, 50),
                       ("y past the bottom edge (x=50, y=200)", 50, 200)):
        try:
            im.draw_flood(100, x, y)
            print(f"BUG: draw_flood start {name}: "
                  "no error raised, coordinates silently accepted")
            failures += 1
        except pyvips.error.Error as e:
            print(f"ok: draw_flood start {name} raised: {e}")

    # 2) A valid in-bounds flood must still work: it fills the connected
    #    region with the ink value.
    im = pyvips.Image.black(64, 64)
    out = im.draw_flood(77, 32, 32)
    probe = (out(32, 32)[0], out(0, 0)[0], out(63, 63)[0])
    if probe == (77, 77, 77):
        print("ok: in-bounds flood from the centre fills the whole black "
              "64x64 region")
    else:
        print(f"BUG: in-bounds flood did not fill: probe={probe} "
              "expected (77, 77, 77)")
        failures += 1

    if failures:
        print(f"BUG REPRODUCED: {failures} check(s) failed", file=sys.stderr)
        return 1
    print("OK: out-of-bounds starts are rejected with an error and valid "
          "floods still work.")
    return 0


if __name__ == "__main__":
    sys.exit(main())