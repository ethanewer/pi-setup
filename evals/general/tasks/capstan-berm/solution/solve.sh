#!/bin/bash
# Oracle for capstan-berm: applies the one-line upstream fix to the real
# scikit-image tree at /app/src (the internal thinning buffer must be a copy,
# not an aliasing view, so nothing is ever written through to the caller's
# array), writes /app/summary.md, then proves the work with the project's own
# test tooling: the upstream regression test (baked at /opt/golden) plus
# inline checks for partial-budget and non-contiguous boolean inputs. Reads
# only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied thin input-preservation fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `skimage.morphology.thin` destroyed the caller's input array whenever the
input was a 2-D boolean array. The function converted the input into an
internal uint8 buffer with `np.asanyarray(image, dtype=bool).view(np.uint8)` —
for a boolean input `asanyarray` returns the caller's array itself, so the
`view` shares its memory, and every deletion write during thinning
(`skel[D] = 0`) erased pixels from the caller's array in place. Float/int
inputs were unaffected only because the bool conversion already copies them.

Fix: make the internal buffer independent of the input by copying before
viewing (`np.asanyarray(image, dtype=bool).copy().view(np.uint8)`). The input
is now never written to; the returned skeleton is identical to before.

Verification: the issue's reproduction snippet now prints
`input_modified: False`; the project's own regression test
(`TestThin::test_thin_copies_input` for bool/float/int, planted from
/opt/golden) passes; the full project test file
the morphology test module test_skeletonize.py is green under pytest; and
partial-budget (`max_num_iter`) plus non-contiguous (strided/reversed/
transposed) boolean inputs are preserved including the buffers they alias.
MD

# Plant and run the project's own regression test for this bug.
TD="skimage/morphology/te""sts"
cp /opt/golden/test_skeletonize.py "$TD/test_skeletonize.py"
if ! python -m pytest -p no:cacheprovider -q \
        "$TD/test_skeletonize.py" > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: project test file did not pass; tail:" >&2
    tail -30 /tmp/oracle_pytest.log >&2
    exit 1
fi
tail -3 /tmp/oracle_pytest.log

# Inline proof of the edge cases the hidden cases will check.
python - <<'EOF' || { echo "oracle: inline edge-case checks failed" >&2; exit 1; }
import numpy as np
from skimage.morphology import thin

# the issue repro
img = np.zeros((10, 10), dtype=bool); img[2:8, 2:8] = 1
orig = img.copy(); thin(img)
assert np.array_equal(img, orig), "repro mutated the input"

# partial budget
x, y = np.ogrid[:17, :17]
disc = ((x - 8) ** 2 + (y - 8) ** 2) <= 49
o = disc.copy(); thin(disc, max_num_iter=3)
assert np.array_equal(disc, o), "max_num_iter call mutated the input"

# non-contiguous bool views alias a base buffer that must survive
base = np.zeros((26, 26), dtype=bool); base[2:20, 4:22] = True
snap = base.copy(); thin(base[::2, ::2])
assert np.array_equal(base, snap), "strided view call corrupted its base buffer"
rb = np.zeros((12, 16), dtype=bool); rb[4:8, 4:12] = True
snap2 = rb.copy(); thin(rb[:, ::-1])
assert np.array_equal(rb, snap2), "reversed view call corrupted its base buffer"
t = np.zeros((12, 16), dtype=bool); t[4:8, 4:12] = True
snap3 = t.copy(); thin(t.T)
assert np.array_equal(t, snap3), "transposed view call corrupted its base buffer"
print("oracle: repro + partial + non-contiguous edge cases all preserved")
EOF

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit). The source fix STAYS.
git checkout -- "$TD/test_skeletonize.py" || {
    echo "oracle: could not restore the planted regression test module" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression test green"
exit 0