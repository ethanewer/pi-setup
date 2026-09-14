#!/bin/bash
# Oracle for jetsam-head: this is the proof the task is passable.
#
# It does the real work an honest solver does:
#   1. writes /app/reproduce.py FIRST (the failing reproduction deliverable),
#   2. applies the upstream fix to the checked-out parent tree at /app/src,
#   3. rebuilds the project incrementally with meson/ninja,
#   4. proves the repaired tree satisfies the reproduction.
# The system-wide /usr build is the pristine parent build; the rebuilt
# library takes effect via LD_LIBRARY_PATH=/app/src/build/libvips, exactly as
# the instruction documents.
set -e

# --- 1. the reproduction deliverable, written before the tree is touched ---
cat > /app/reproduce.py <<'REPRO'
#!/usr/bin/env python3
"""Reproduction: ICC profile import of a float (0..1) RGB image goes black.

Run against the buggy parent build this exits non-zero (the import comes back
black, average 0); against a repaired build it exits 0.
Use absolute paths so it works from any working directory.
"""
import pyvips

SRGB = "/app/src/test/test-suite/images/sRGB.icm"
JPEG = "/app/src/test/test-suite/images/sample.jpg"

test = pyvips.Image.new_from_file(JPEG)
test_float = (test / 255).cast(pyvips.BandFormat.FLOAT)
from_float = test_float.icc_import(input_profile=SRGB)

avg = from_float.avg()
print("float icc_import average:", avg)
assert avg > 1.0, "bug: float image ICC import came out black (avg=%r)" % (avg,)
print("reproduction passes: the float import is not black")
REPRO
chmod +x /app/reproduce.py

# --- 2. apply the upstream fix to the working tree ---------------------------
cd /app/src
patch -p1 --forward -s < /solution/icc_float_input_fix.patch

# --- 3. rebuild; the fixed library lands in /app/src/build/libvips -----------
ninja -C build -j1

# --- 4. prove the repaired tree satisfies the reproduction -------------------
LD_LIBRARY_PATH=/app/src/build/libvips python3 /app/reproduce.py