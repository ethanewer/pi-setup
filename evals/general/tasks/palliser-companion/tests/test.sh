#!/bin/bash
# Verifier for palliser-companion: an upstream-clone debugging task on
# pytorch/vision.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# torchvision.transforms.v2's elastic kernel raises IndexError for any
# bounding box whose corner reaches the canvas width/height (the corner
# indexes the displacement grid with the raw ceil()ed coordinate), instead
# of warping the box.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, no new non-bytecode files
#      appeared inside the torchvision package, and the repair is non-empty);
#   0.5 asserts module origin: under an isolated interpreter the installed
#      torchvision.transforms.v2.functional._geometry module resolves to a
#      file under /app/src (the deliverable), so a fix that edits /opt/venv
#      or an import hook cannot fake a pass;
#   1. executes the agent's own reproduction deliverable /app/repro_elastic.py
#      twice: against a pristine copy of the pre-fix module (must FAIL, i.e.
#      exit non-zero) and against the repaired tree (must exit 0);
#   2. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   3. runs the project's own existing TestElastic suite from the tree,
#      proving the fix broke nothing else;
#   4. runs at least two authored hidden cases (other box formats and float64
#      near-boundary coordinates; a batch of edge-touching boxes under a
#      non-identity displacement plus the BoundingBoxes wrapper path) that the
#      upstream test does not cover.
#
# All suite runs go through an isolated interpreter (python3 -I -S with an
# explicit sys.path of the venv site-packages plus /app/src/test), so
# sitecustomize / .pth hooks planted by an agent are invisible to the verdict.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PY=/opt/venv/bin/python
REPRO=/app/repro_elastic.py
PARENT_SHA=8a5946ed6bce34bfeb26b964fc8875447d841ae8
FIX_SHA=3cbf38e82f6d0e35cfa8363b165b5a372fcfbfff
GOLDEN=/opt/golden/test_transforms_v2.py
GOLDEN_ASSET=/opt/golden/assets/gaussian_blur_opencv_results.pt
GOLDEN_PARENT_GEOMETRY=/opt/golden/parent_geometry.py
GOLDEN_SHA256=09973e3da3c3a0c96fcabafac0f16f4a3b4d621f8c660c4cbe36173ed2275028
ASSET_SHA256=31e0a4bf9ab28555dcfb8ebb9a94814c1e1aabc225974779ac296519e0b0a1e2
PARENT_GEOMETRY_SHA256=0786c138dd3314c41201996b0792dd0a2203b2fc2b651b743bb3d0d857cdb8ee

# venv site-packages, resolved dynamically so the isolated launcher below
# sees the same installed packages pytest would.
SP="$($PY -c 'import sysconfig; print(sysconfig.get_path("purelib"))' 2>/dev/null || true)"
if [ -z "$SP" ] || [ ! -d "$SP" ] || [ ! -d "$SP/torchvision" ]; then
  echo "FAIL: could not resolve the venv site-packages (SP='${SP:-<empty>}')" >&2
  reward=0
fi

iso_pytest () {  # iso_pytest LABEL OUT ...args   (pytest argv, run from /)
  label="$1"; out="$2"; shift 2
  if ( cd / \
       && "$PY" -I -S -c "
import sys
sys.path[:0] = ['$SP', '$SRC/test']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$@" -c "$SRC/pytest.ini" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# Only a plain modification of the single source file may appear.  Untracked
# files (a conftest.py planted at the repo root would let the agent skip whole
# suites) are rejected too; only interpreter bytecode caches (__pycache__) are
# tolerated.
bad=$(printf '%s\n' "$porcelain" \
      | grep -v '^ M torchvision/transforms/v2/functional/_geometry.py$' \
      | grep -vE '^\?\? .*__pycache__' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only torchvision/transforms/v2/functional/_geometry.py may be modified; no new untracked files are allowed anywhere under /app/src):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- torchvision/transforms/v2/functional/_geometry.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0.5 module origin: the verdict must measure /app/src -------------
echo "== module origin (isolated interpreter) =="
if "$PY" -I -S -c "
import os, sys
sys.path[:0] = ['$SP']
from torchvision.transforms.v2 import functional as F
import torchvision.transforms.v2.functional._geometry as geom
from torchvision.transforms.v2.functional import elastic_bounding_boxes
import inspect
af = geom.__file__
bf = os.path.realpath(geom.__file__)
print('geometry.py path:', af)
print('geometry.py real path:', bf)
assert os.path.islink(af), (af, 'is not a symlink into the deliverable')
assert os.readlink(af) == '$SRC/torchvision/transforms/v2/functional/_geometry.py', os.readlink(af)
assert bf == '$SRC/torchvision/transforms/v2/functional/_geometry.py', (bf, '$SRC/torchvision/transforms/v2/functional/_geometry.py')
# the function the tests call must BE the function defined in the deliverable
assert geom.elastic_bounding_boxes is elastic_bounding_boxes, 'elastic_bounding_boxes rebound from outside _geometry.py'
mf = os.path.realpath(inspect.getsourcefile(elastic_bounding_boxes) or '')
print('elastic_bounding_boxes source:', mf)
assert mf == '$SRC/torchvision/transforms/v2/functional/_geometry.py', (mf, '$SRC/torchvision/transforms/v2/functional/_geometry.py')
" > /tmp/origin.out 2>&1; then
  echo "ok: torchvision.transforms.v2.functional resolves to the deliverable tree"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: the installed torchvision does not resolve to the deliverable under an isolated interpreter:" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. the agent's own reproduction deliverable ----------------------
echo "== agent reproduction =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: /app/repro_elastic.py (the required reproduction deliverable) does not exist" >&2
  reward=0
elif [ ! -s "$GOLDEN_PARENT_GEOMETRY" ] \
     || [ "$(sha256sum "$GOLDEN_PARENT_GEOMETRY" | awk '{print $1}')" != "$PARENT_GEOMETRY_SHA256" ]; then
  echo "FAIL: pristine parent module missing from the image (pre-fix re-run impossible)" >&2
  reward=0
else
  # (a) against a pristine copy of the pre-fix code: must FAIL (exit non-zero)
  PREFIX=/tmp/prefix-lib
  rm -rf "$PREFIX" && mkdir -p "$PREFIX"
  cp -a "$SP/torchvision" "$PREFIX/torchvision"
  rm -f "$PREFIX/torchvision/transforms/v2/functional/_geometry.py"
  cp "$GOLDEN_PARENT_GEOMETRY" "$PREFIX/torchvision/transforms/v2/functional/_geometry.py"
  rm -rf "$PREFIX/torchvision/transforms/v2/functional/__pycache__" "$PREFIX/torchvision/transforms/v2/__pycache__"
  rm -rf "$PREFIX/torchvision/transforms/v2/__pycache__"
  if ( cd / && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PREFIX:$SP" timeout 120 "$PY" "$REPRO" > /tmp/repro_pre.out 2>&1 ); then
    echo "FAIL: the reproduction succeeded against the PRISTINE pre-fix code (it does not demonstrate the bug)" >&2
    cat /tmp/repro_pre.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: reproduction fails against the pre-fix module (exit non-zero)"
    sed 's/^/    /' /tmp/repro_pre.out | head -6
  fi
  # (b) against the repaired tree: must succeed (exit 0)
  rm -rf "$PREFIX"
  if ( cd / && PYTHONDONTWRITEBYTECODE=1 timeout 120 "$PY" "$REPRO" > /tmp/repro_post.out 2>&1 ); then
    echo "ok: reproduction succeeds against the repaired tree"
    sed 's/^/    /' /tmp/repro_post.out | head -6
  else
    echo "FAIL: the reproduction failed against the repaired tree" >&2
    cat /tmp/repro_post.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_transforms_v2.py does not match the bytes extracted from the upstream fix commit" >&2
  reward=0
elif [ ! -s "$GOLDEN_ASSET" ] || [ "$(sha256sum "$GOLDEN_ASSET" | awk '{print $1}')" != "$ASSET_SHA256" ]; then
  echo "FAIL: /opt/golden/assets/gaussian_blur_opencv_results.pt does not match the upstream fix-commit bytes" >&2
  reward=0
else
  iso_pytest "golden test_kernel_bounding_boxes_at_canvas_boundary" /tmp/golden.out \
    "$GOLDEN::TestElastic::test_kernel_bounding_boxes_at_canvas_boundary" \
    || true
fi

# ---------- 3. the project's own existing elastic-distortion suite -----------
echo "== the project's own existing TestElastic suite =="
iso_pytest "existing test/test_transforms_v2.py::TestElastic" /tmp/own.out \
  "$SRC/test/test_transforms_v2.py::TestElastic" \
  || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd / \
       && "$PY" -I -S -c "
import sys
sys.path[:0] = ['$SP', '$SRC/test']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$case" -c "$SRC/pytest.ini" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0