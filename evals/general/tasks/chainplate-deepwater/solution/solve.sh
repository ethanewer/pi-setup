#!/bin/bash
# Oracle for chainplate-deepwater: applies the real upstream fix to the
# integer bounding-box conversion in the real pytorch/vision tree at /app/src,
# refreshes the venv mirror, writes /app/summary.md, and proves the fix with
# the project's own test suite plus the upstream regression test (extracted
# from the fix commit into /opt/golden at image-build time). Reads only
# /app, /solution and /opt/golden -- never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied integer-conversion fix"

# Refresh the installed-package mirror so /app/env runs the fixed code.
FIXED=/app/src/torchvision/transforms/v2/functional/_meta.py
cp "$FIXED" /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_meta.py
find /app/env/lib/python3.12/site-packages/torchvision -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
echo "oracle: venv mirror refreshed"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: converting integer-typed bounding boxes from center/width/height form
(CXCYWH) to corner form (XYXY) could emit a negative top or left corner even
for boxes fully inside the canvas, whenever the box had an odd width or
height. Localised to `torchvision/transforms/v2/functional/_meta.py`,
function `_cxcywh_to_xyxy`: the half-extents were computed on the integer
tensor with `div(-2, rounding_mode="floor")`, which rounds -h/2 DOWN (i.e.
the half UP) for odd dimensions. For the reproduction box the true top edge
is cy - h/2 = 6 - 6.5 = -0.5, whose truncation toward zero is 0, but the
floor-rounding trick produced -1, a corner one pixel above the canvas. The
floating-point path was correct, and so was the independent reference in
`torchvision.ops._box_convert._box_cxcywh_to_xyxy`.

Fix: match the ops-module semantics exactly. Upcast integer input to float,
compute both halves with true division (`w / 2`), do the corner arithmetic in
float, and truncate back to the original integer dtype on the way out
(preserving the in-place behaviour by writing the truncated result back into
the input tensor). Float inputs take the unchanged, exact path.

Verification:
- `/opt/repro.py` prints `OK` (converts `[[5, 6, 10, 13]]` CXCYWH to
  `[[0, 0, 10, 12]]` XYXY on int64).
- Upstream regression test `TestConvertBoundingBoxFormat::test_cxcywh_to_xyxy_odd_dimensions`
  (planted from /opt/golden) passes.
- The project's own `TestConvertBoundingBoxFormat` class passes (122 passed,
  48 skipped, 12 xfailed) -- every conversion checked element-for-element
  against the `torchvision.ops.box_convert` reference, for int64/float32 and
  out-of-place/in-place alike.
MD

# Prove the fix with the project's own test runner: plant the upstream
# regression test (golden bytes from /opt/golden) and run it offline from a
# neutral CWD (running from /app/src would shadow the source tree onto
# sys.path and defeat the installed-package mirror).
cp /opt/golden/test_transforms_v2.py test/test_transforms_v2.py
cd /tmp
if ! /app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
        -k test_cxcywh_to_xyxy_odd_dimensions -p no:cacheprovider -o addopts='' \
        --tb=line > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -25 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -qE "1 passed" /tmp/oracle_golden.log || {
    echo "oracle: expected '1 passed' summary; tail:" >&2
    tail -15 /tmp/oracle_golden.log >&2
    exit 1
}
if ! /app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
        -k "TestConvertBoundingBoxFormat" -p no:cacheprovider -o addopts='' \
        -q > /tmp/oracle_class.log 2>&1; then
    echo "oracle: TestConvertBoundingBoxFormat did not pass; tail:" >&2
    tail -25 /tmp/oracle_class.log >&2
    exit 1
fi
grep -qE "passed" /tmp/oracle_class.log || {
    echo "oracle: expected a passing pytest summary; tail:" >&2
    tail -15 /tmp/oracle_class.log >&2
    exit 1
}
if ! /app/env/bin/python /opt/repro.py > /tmp/oracle_repro.log 2>&1; then
    echo "oracle: direct reproducer did not print OK; tail:" >&2
    tail -10 /tmp/oracle_repro.log >&2
    exit 1
fi
grep -q "^OK$" /tmp/oracle_repro.log || {
    echo "oracle: reproducer output missing OK" >&2
    exit 1
}

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
cd /app/src
git restore --worktree --source=HEAD -- test/test_transforms_v2.py || {
    echo "oracle: could not restore test/test_transforms_v2.py" >&2
    exit 1
}

echo "oracle: fix applied, summary written, upstream + project suites green"
exit 0