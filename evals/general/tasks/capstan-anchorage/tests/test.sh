#!/bin/bash
# Verifier for capstan-anchorage: an upstream-clone debugging task on
# pytorch/vision.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# torchvision.ops.masks_to_boxes crashes with RuntimeError on any mask that
# has no foreground pixels (unconditional torch.min/torch.max over an empty
# coordinate set), instead of returning the degenerate box [0, 0, 0, 0].
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, no new non-bytecode files
#      appeared inside the torchvision package, and the repair is non-empty);
#   0.5 asserts module origin: under an isolated interpreter the installed
#      torchvision.ops.boxes module resolves to a file under /app/src (the
#      deliverable), so a fix that edits /opt/venv or an import hook cannot
#      fake a pass;
#   1. runs the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing masks-to-boxes tests from the tree,
#      proving the fix broke nothing else;
#   3. runs at least three authored hidden cases (other dtypes, non-contiguous
#      views, degenerate single-pixel/single-column/full masks) that the
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
PARENT_SHA=df421b423f714eb3ae22cab2b0e6e7a6f6bb29be
FIX_SHA=b32ce3d020f77155de4ffb1fd8868a0880f03dbc
GOLDEN=/opt/golden/test_ops.py
GOLDEN_DICT=/opt/golden/optests_failures_dict.json
GOLDEN_SHA256=9367f3869f1fc40f224dda56af14e8ad022d09fd9b21aad72a14d22323eb4542
GOLDEN_DICT_SHA256=d313617c094a2175a2fbb3940bba1457036951d73f8a02c9c2943448ac14d0bf

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
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M torchvision/ops/boxes.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only torchvision/ops/boxes.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? torchvision/' | grep -v '__pycache__' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new non-bytecode files were added inside the torchvision package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- torchvision/ops/boxes.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0.5 module origin: the verdict must measure /app/src -------------
echo "== module origin (isolated interpreter) =="
if "$PY" -I -S -c "
import os, sys
sys.path[:0] = ['$SP']
import torchvision
import torchvision.ops.boxes as boxes
from torchvision.transforms.v2.functional import cvcuda_to_tensor, to_cvcuda_tensor
from torchvision.ops import masks_to_boxes
import inspect
af = torchvision.__file__
bf = os.path.realpath(boxes.__file__)
print('torchvision file:', af)
print('boxes.py real file:', bf)
assert af.startswith('$SP/'), af
assert os.path.islink(boxes.__file__), boxes.__file__
assert os.readlink(boxes.__file__) == '$SRC/torchvision/ops/boxes.py', os.readlink(boxes.__file__)
assert bf == '$SRC/torchvision/ops/boxes.py', (bf, '$SRC/torchvision/ops/boxes.py')
# The function the tests import must BE the function defined in the deliverable:
# rebinding torchvision.ops.masks_to_boxes from an edited site-packages module
# (e.g. torchvision/ops/__init__.py) or delegating out of boxes.py must not pass.
assert boxes.masks_to_boxes is masks_to_boxes, \\
    'torchvision.ops.masks_to_boxes is not the boxes.py module-level function (an import override is in effect)'
mf = os.path.realpath(inspect.getsourcefile(masks_to_boxes) or '')
print('masks_to_boxes source file:', mf)
assert mf == '$SRC/torchvision/ops/boxes.py', (mf, '$SRC/torchvision/ops/boxes.py')
" > /tmp/origin.out 2>&1; then
  echo "ok: torchvision resolves to the venv site-packages and ops/boxes.py to the deliverable"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: the installed torchvision does not resolve to the deliverable under an isolated interpreter:" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression tests -------------------------
echo "== golden test (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_ops.py does not match the bytes extracted from the upstream fix commit (sha256 expected $GOLDEN_SHA256)" >&2
  reward=0
elif [ "$(sha256sum "$GOLDEN_DICT" | awk '{print $1}')" != "$GOLDEN_DICT_SHA256" ]; then
  echo "FAIL: /opt/golden/optests_failures_dict.json does not match the upstream fix-commit bytes" >&2
  reward=0
else
  iso_pytest "golden test_empty_masks + test_mixed_empty_and_non_empty_masks" /tmp/golden.out \
    "$GOLDEN::TestMasksToBoxes::test_empty_masks" \
    "$GOLDEN::TestMasksToBoxes::test_mixed_empty_and_non_empty_masks" \
    || true
fi

# ---------- 2. the project's own existing masks-to-boxes suite ---------------
echo "== the project's own existing masks-to-boxes tests =="
iso_pytest "existing test/test_ops.py::TestMasksToBoxes" /tmp/own.out \
  "$SRC/test/test_ops.py::TestMasksToBoxes" \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
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