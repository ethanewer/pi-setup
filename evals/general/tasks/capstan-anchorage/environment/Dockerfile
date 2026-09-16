# capstan-anchorage: pytorch/vision masks_to_boxes crashes on masks with no
# foreground pixels (all-zero masks); upstream issue #9357.
#
# The image clones pytorch/vision SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree).  The project's own regression
# test for the bug is extracted from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository).  The fix commit is
# the direct child of the parent, so it is NOT reachable from the depth-1
# parent clone; the extraction uses a throwaway bare clone that is deleted.
#
# torch/torchvision are CPU wheels (torchvision 0.25.0 still ships the bug).
# Test-module imports (repo helper test/common_utils.py) need a few
# pure-python names the 0.25.0 wheel strips, so the checkout's newer
# transforms/v2/functional source is overlaid over the wheel.  The module
# whose EXECUTION must track the agent's edits, torchvision/ops/boxes.py, is
# symlinked from the wheel install to the checked-out tree, so the code the
# tests run is exactly the code in the deliverable /app/src.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=df421b423f714eb3ae22cab2b0e6e7a6f6bb29be
ARG FIX_SHA=b32ce3d020f77155de4ffb1fd8868a0880f03dbc

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A shallow fetch of exactly the parent SHA; the fix commit is a descendant
# so it cannot exist in this object store.  Fail closed if upstream moves.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin df421b423f714eb3ae22cab2b0e6e7a6f6bb29be \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
# test_ops.py at this era calls optests.generate_opcheck_tests() with a
# failures-dict path relative to __file__, so the dict is extracted alongside.
RUN git init -q --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin b32ce3d020f77155de4ffb1fd8868a0880f03dbc \
 && mkdir -p /opt/golden \
 && git show b32ce3d020f77155de4ffb1fd8868a0880f03dbc:test/test_ops.py \
      > /opt/golden/test_ops.py \
 && git show b32ce3d020f77155de4ffb1fd8868a0880f03dbc:test/optests_failures_dict.json \
      > /opt/golden/optests_failures_dict.json \
 && test -s /opt/golden/test_ops.py \
 && grep -q "test_empty_masks" /opt/golden/test_ops.py \
 && grep -q "test_mixed_empty_and_non_empty_masks" /opt/golden/test_ops.py \
 && test "$(sha256sum /opt/golden/test_ops.py | awk '{print $1}')" = "9367f3869f1fc40f224dda56af14e8ad022d09fd9b21aad72a14d22323eb4542" \
 && cd / && rm -rf /tmp/fixsrc

# ---- python env: era-appropriate CPU wheels, pytest from PyPI ---------------
ENV PATH=/opt/venv/bin:$PATH \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN python3 -m venv /opt/venv \
 && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu \
      'torch==2.10.0+cpu' 'torchvision==0.25.0+cpu'

RUN pip install --no-cache-dir 'pytest==8.4.2'

# ---- wire the running code to the deliverable ------------------------------
# Overlay the checkout's newer pure-python transforms/v2/functional on the
# wheel (the repo's test helper common_utils.py imports cvcuda-era names the
# 0.25.0 wheel strips), then symlink boxes.py so the executed code IS the
# checked-out tree that the agent edits.  Verify import + linkage at build.
RUN SP=$(/opt/venv/bin/python -c 'import sysconfig; print(sysconfig.get_path("purelib"))') \
 && test -d "$SP/torchvision" \
 && cp -f /app/src/torchvision/transforms/v2/functional/*.py \
           "$SP/torchvision/transforms/v2/functional/" \
 && rm -rf "$SP/torchvision/transforms/v2/functional/__pycache__" \
 && ln -sf /app/src/torchvision/ops/boxes.py "$SP/torchvision/ops/boxes.py" \
 && test "$(readlink "$SP/torchvision/ops/boxes.py")" = "/app/src/torchvision/ops/boxes.py" \
 && /opt/venv/bin/python - <<'PY'
import os
import torch, torchvision
import torchvision.ops.boxes as boxes
from torchvision.transforms.v2.functional import cvcuda_to_tensor, to_cvcuda_tensor
assert torchvision.__version__.startswith("0.25.0"), torchvision.__version__
assert os.path.realpath(boxes.__file__) == "/app/src/torchvision/ops/boxes.py", boxes.__file__
assert torch.__version__ == "2.10.0+cpu", torch.__version__
print("build-time import check OK:", torch.__version__, torchvision.__version__)
PY

# ---- make the tree writable for a uid-1000 trial, then ship files ----------
RUN chmod -R a+rwX /app/src

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app && chmod +x /app/run_pytest.sh /app/probe_masks_to_boxes.py

CMD ["/bin/bash"]