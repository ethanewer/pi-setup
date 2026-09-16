#!/usr/bin/env python3
"""jetsam-head hidden case 1 (case-png).

The upstream regression test uses the 8-bit JPEG fixture sample.jpg converted
to FLOAT. This case drives the same ICC input-format code path from different
inputs: the 16-bit PNG fixture sample.png (whose values span the full 16-bit
range), rescaled to the usual 0..1 float range, plus a reference through the
project's native 16-bit path.

Passes only if the (0..1) float import of the PNG is non-black (average well
above 10, like the 8-bit/16-bit imports) AND matches the native 16-bit import
within a tight per-pixel tolerance (max abs difference < 3).
"""
import sys
import pyvips

SRGB = "/app/src/test/test-suite/images/sRGB.icm"
PNG = "/app/src/test/test-suite/images/sample.png"


def main():
    test = pyvips.Image.new_from_file(PNG)

    from_16bit = test.icc_import(input_profile=SRGB)
    from_float = (test / 65535).cast(pyvips.BandFormat.FLOAT) \
        .icc_import(input_profile=SRGB)

    favg = from_float.avg()
    if not favg > 10.0:
        print("FAIL: float PNG icc_import came out black, avg=%r" % favg)
        return 1
    mx = (from_16bit - from_float).abs().max()
    if not mx < 3:
        print("FAIL: float PNG import diverges from 16-bit import, maxdiff=%r" % mx)
        return 1
    print("case-png ok: float avg=%r maxdiff_16bit=%r" % (favg, mx))
    return 0


if __name__ == "__main__":
    sys.exit(main())