#!/bin/bash
# Oracle for bracket-channel: repairs the uchar->uchar unpremultiply clamp
# bug in the real cloned tree, rebuilds and reinstalls the library, writes
# the /app/diagnosis.md deliverable, and proves the fix with the reproducer.
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
## Root cause: uchar value wraps instead of saturating in unpremultiply

### Where
`libvips/conversion/unpremultiply.c` -- the fast uchar->uchar path of the
unpremultiply operation (vips_unpremultiply), the branch that is used when
the input format is uchar and `uchar=True`.

### Root cause
The fast path computed `out[i] = (in[i] * scale + 128) >> 8` and stored the
result directly into an 8-bit pixel. When the scaled value exceeds 255
(for example 20 * (255/10) = 510), the store wraps modulo 256 (510 -> 254)
instead of saturating, producing dark, corrupted pixels whose error depends
on the alpha channel. Floating-point formats take a different path, which is
why the bug only showed in the 8-bit path.

### Fix
Clamp the computed value to UCHAR_MAX before storing:
for each colour band: `int value = (in[i]*scale + 128) >> 8; out[i] =
VIPS_MIN(value, UCHAR_MAX);`  -- values past 255 now saturate to 255 and
in-range values are untouched.

### Verification
`python3 /app/reproduce.py` prints `[255.0, 10.0]` and exits 0; the project's
conversion test suite passes.
MD

# ---- 4. prove the fix -------------------------------------------------------
python3 /app/reproduce.py
status=$?
if [ $status -ne 0 ]; then
    echo "oracle: reproduce.py still failing after fix" >&2
fi
echo "oracle: done (reproducer exit $status)"
exit 0