#!/usr/bin/env python3
"""Oracle fix for bracket-channel.

Applies the minimal, upstream-shaped repair to the fast uchar->uchar
unpremultiply path in /app/src/libvips/conversion/unpremultiply.c: clamp the
computed value to UCHAR_MAX before storing it, exactly as the upstream fix
does. This script edits the clone; it never reads /tests.
"""
import re
import sys

PATH = "/app/src/libvips/conversion/unpremultiply.c"

src = open(PATH, encoding="utf-8").read()

# The buggy fast path: value computed, then stored directly into an 8-bit
# pixel, so anything above 255 wraps modulo 256 instead of saturating.
buggy = re.compile(
    r"for \(i = 0; i < bands - 1; i\+\+\)\n(\s*)"
    r"out\[i\] = \(in\[i\] \* scale \+ 128\) >> 8;"
)
fixed = (
    "for (i = 0; i < bands - 1; i++) {\n"
    "\\1int value = (in[i] * scale + 128) >> 8;\n"
    "\\1out[i] = VIPS_MIN(value, UCHAR_MAX);\n"
    "\\1}"
)
src, n = buggy.subn(fixed, src)
if n != 1:
    print(f"oracle: expected exactly one fast-path site, found {n}", file=sys.stderr)
    sys.exit(1)

open(PATH, "w", encoding="utf-8").write(src)
print("oracle: clamped uchar fast path to UCHAR_MAX in unpremultiply.c")