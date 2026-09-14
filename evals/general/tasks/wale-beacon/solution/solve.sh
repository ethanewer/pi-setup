#!/bin/bash
# Oracle for wale-beacon: applies the one-source-file fix to the real
# pytorch/vision tree at /app/src (the JPEG kernel must copy the non-contiguous
# leading dimensions instead of rejecting their stride pattern when it flattens
# the batch), writes /app/repro.py and /app/summary.md, then proves the work:
# the reproduction must fail against the pristine pre-fix module baked at
# /opt/prefix and pass against the repaired tree; the upstream regression test
# baked at /opt/golden must pass on the repaired tree. Reads only /app,
# /solution and /opt, never /tests.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the JPEG non-contiguous leading-dimension fix"

cat > /app/repro.py <<'PY'
#!/app/env/bin/python
# Failing reproduction for the wale-beacon symptom: JPEG re-compression of a
# non-contiguous video/image batch raises a stride/view error on the unfixed
# tree. Exits 0 iff the transform of the non-contiguous input succeeds and is
# element-identical to the transform of the contiguous copy.
import sys
import torch
from torchvision.transforms.v2 import functional as F

image = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)  # (3,2,3,16,16)
assert not image.is_contiguous(), "input must be non-contiguous"

out = F.jpeg_image(image, quality=75)
ref = F.jpeg_image(image.contiguous(), quality=75)

ok = out.shape == image.shape and out.dtype == image.dtype and torch.equal(out, ref)
print("input shape:", tuple(image.shape), "non-contiguous jpeg output matches contiguous run:", ok)
sys.exit(0 if ok else 1)
PY
chmod +x /app/repro.py

cat > /app/summary.md <<'MD'
# change summary

Bug: `torchvision.transforms.v2.functional.jpeg` (kernels `jpeg_image` /
`jpeg_video`) rejected any input whose leading (batch/frame) dimensions were
not memory-contiguous. It flattened those dimensions with a strict view that
requires a contiguous stride pattern, so a transposed or strided video/image
batch raised a "view size is not compatible with input tensor's size and
stride" RuntimeError before any encoding happened, while contiguous tensors
of the same shape worked.

Fix: in the JPEG kernel, flatten the leading dimensions with a
copy-capable reshape instead of the strict view, so a non-contiguous batch
is handled and produces the same pixels as its contiguous copy.

Verified: /app/repro.py fails on the pristine pre-fix module (baked at
/opt/prefix) and passes on this tree; the project's own TestJPEG tests and
the upstream regression test (baked at /opt/golden) pass.
MD

# ---- prove both directions ----
SITE=/app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_augment.py
FUNCDIR=/app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional
restore() {
    rm -f "$SITE"
    ln -s /app/src/torchvision/transforms/v2/functional/_augment.py "$SITE"
    rm -rf "$FUNCDIR/__pycache__"
}
trap restore EXIT

# pre-fix direction: must FAIL
rm -f "$SITE"
cp /opt/prefix/_augment.py "$SITE"
rm -rf "$FUNCDIR/__pycache__"
if /app/env/bin/python /app/repro.py > /tmp/oracle-prefix.out 2>&1; then
    echo "oracle: repro PASSED against the pristine pre-fix module (expected failure)" >&2
    head -10 /tmp/oracle-prefix.out >&2
    exit 1
fi
echo "oracle: repro fails on the pristine pre-fix module, as required"

# repaired direction: must PASS
restore
if ! /app/env/bin/python /app/repro.py > /tmp/oracle-fixed.out 2>&1; then
    echo "oracle: repro FAILED on the repaired tree (expected pass)" >&2
    head -10 /tmp/oracle-fixed.out >&2
    exit 1
fi
cat /tmp/oracle-fixed.out

# upstream regression test on the repaired tree: must PASS
if ! ( cd /tmp && PYTHONDONTWRITEBYTECODE=1 /app/env/bin/python -m pytest \
        /opt/golden/test_kernel_non_contiguous_leading_dimensions.py \
        -p no:cacheprovider -q > /tmp/oracle-golden.out 2>&1 ); then
    echo "oracle: golden test FAILED on the repaired tree" >&2
    tail -20 /tmp/oracle-golden.out >&2
    exit 1
fi
grep -q "1 passed" /tmp/oracle-golden.out || {
    echo "oracle: golden test did not report 1 passed" >&2
    exit 1
}
echo "oracle: upstream regression test passes on the repaired tree; done"