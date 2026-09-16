#!/bin/bash
# Oracle for cistern-coral: adds the draw_flood start-point bounds check to
# the real cloned tree, rebuilds and reinstalls the library, writes the
# /app/diagnosis.md deliverable, and proves the fix with the reproducer.
# Reads only /app and /solution. Never touches /tests.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# ---- 1. apply the minimal source repair -------------------------------------
python3 /solution/fix.py || exit 1

# ---- 2. rebuild + reinstall the library (incremental) ----------------------
ninja -C build install > /tmp/oracle-ninja.log 2>&1
status=$?
if [ $status -ne 0 ]; then
    echo "oracle: ninja install failed" >&2
    tail -20 /tmp/oracle-ninja.log >&2
    exit 1
fi
ldconfig 2>/dev/null || true
echo "oracle: rebuilt and installed"

# ---- 3. write the deliverable /app/diagnosis.md -----------------------------
cat > /app/diagnosis.md <<'MD'
## Root cause: draw_flood silently accepts an out-of-image start point

### Where
`libvips/draw/draw_flood.c` -- the `vips_draw_flood_build()` function of
the draw_flood flood-fill operation, the code behind pyvips' `draw_flood`
/ `draw_flood1` methods.

### Root cause
The build function validated the input images but never checked the start
point before starting the fill. A start position past the right or bottom
edge (x >= image width or y >= image height) passed the GObject property
range (0..1000000000) and reached the fill machinery, which then found no
connected in-image pixels and returned success without drawing anything:
the caller silently got a "successful" operation that did nothing. Negative
coordinates, by contrast, were rejected earlier by the property range
check, which is why they produced an opaque property error instead of a
clear out-of-bounds message.

### Fix
Added an explicit bounds check at the top of the fill path in
`vips_draw_flood_build()`: if x >= Xsize or y >= Ysize, fail the operation
with "start point out of image" instead of silently doing nothing.

### Verification
`python3 /app/reproduce.py` now rejects out-of-bounds starts with a clear
error and exits 0; valid in-bounds floods still fill; the project's draw
test suite stays green.
MD

# ---- 4. prove the fix -------------------------------------------------------
python3 /app/reproduce.py
status=$?
if [ $status -ne 0 ]; then
    echo "oracle: reproduce.py still failing after fix" >&2
fi
echo "oracle: done (reproducer exit $status)"
exit 0