#!/usr/bin/env python3
"""jetsam-head hidden case 2 (case-double).

The upstream regression test only exercises the FLOAT band format on a real
photo. This case exercises the same ICC input-format code path from DOUBLE
band-format inputs and from synthetic constant colours the photo test never
contains: a dark but legitimately coloured image, a near-black image, and a
bright image. A cheat that hardcodes the photo's expected average or routes
float input through the 8-bit path cannot satisfy all of these at once.

All colour checks use the Lab L channel (band 0): the overall image average
is not a valid "non-black" proxy for constant colours because the a/b bands
legitimately go negative. Passes only if:
  - the DOUBLE (0..1) import of a dark constant colour has a non-black L
    (L > 1) and matches the equivalent 8-bit import within maxdiff < 3;
  - a near-black double import stays darker (lower L) than the dark colour;
  - two different colours keep two clearly different L values (a
    constant/hardcoded answer would collapse them).
"""
import sys
import pyvips

SRGB = "/app/src/test/test-suite/images/sRGB.icm"


def icc_import_double(rgb):
    im = pyvips.Image.black(64, 64) + [rgb[0], rgb[1], rgb[2]]
    return im.cast(pyvips.BandFormat.DOUBLE).icc_import(input_profile=SRGB)


def l_of(im):
    return im.extract_band(0).avg()


def main():
    dark = icc_import_double((0.05, 0.1, 0.3))
    near_black = icc_import_double((0.001, 0.002, 0.003))
    bright = icc_import_double((0.9, 0.9, 0.9))

    dark_l = l_of(dark)
    near_l = l_of(near_black)
    bright_l = l_of(bright)

    if not dark_l > 1.0:
        print("FAIL: dark DOUBLE import came out black, L=%r" % dark_l)
        return 1
    if not near_l < dark_l:
        print("FAIL: near-black import (L=%r) not darker than dark (L=%r)" % (near_l, dark_l))
        return 1
    if not abs(bright_l - dark_l) > 20:
        print("FAIL: distinct colours collapsed, dark L=%r bright L=%r" % (dark_l, bright_l))
        return 1

    u8 = (pyvips.Image.black(64, 64) + [0.05 * 255, 0.1 * 255, 0.3 * 255]) \
        .cast(pyvips.BandFormat.UCHAR)
    u8_import = u8.icc_import(input_profile=SRGB)
    mx = (dark - u8_import).abs().max()
    if not mx < 3:
        print("FAIL: dark DOUBLE import diverges from 8-bit path, maxdiff=%r" % mx)
        return 1

    print("case-double ok: dark L=%r near L=%r bright L=%r maxdiff_8bit=%r"
          % (dark_l, near_l, bright_l, mx))
    return 0


if __name__ == "__main__":
    sys.exit(main())