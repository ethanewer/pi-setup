# palliser-companion: pytorch/vision v2 elastic-distortion kernel crashes on
# bounding boxes that touch the canvas boundary (upstream issue #9394).
#
# The image clones pytorch/vision SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree the agent receives).  The
# project's own regression test for the bug is extracted from the FIX commit at
# build time into /opt/golden/ (upstream bytes never enter this repository).
# The pristine PARENT version of the module the agent must repair is also
# captured to /opt/golden/parent_geometry.py so the verifier can re-run the
# agent's reproduction against the pre-fix tree concept.  The fix commit is
# the direct child of the parent, so it is NOT reachable from the depth-1
# parent clone; the extraction uses a throwaway bare clone that is deleted.
#
# The code that Python runs under torchvision.transforms.v2.functional is the
# checked-out tree: the checkout's transforms/v2 sources are overlaid on the
# torchvision 0.29.0 wheel (the released wheel strips cvcuda-era names the
# repo's test helpers and the era-matched modules need), and
# functional/_geometry.py -- the module the agent must edit -- is symlinked
# from the wheel install back into /app/src, so edits to the deliverable are
# live.
#
# torch 2.14.0 deprecates torch.jit.script with a FutureWarning, and the era's
# test module elevates ALL warnings to errors (pytestmark filterwarnings
# "error"); without intervention the project's own kernel tests cannot run in
# this image regardless of the bug.  We neutralize that single deprecation
# warning in the pinned torch install so the project's suite behaves the way it
# did when it was written (this changes no behavior under test).
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=8a5946ed6bce34bfeb26b964fc8875447d841ae8
ARG FIX_SHA=3cbf38e82f6d0e35cfa8363b165b5a372fcfbfff

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A shallow fetch of exactly the parent SHA; the fix commit is its direct
# child, so it cannot exist in this object store.  Fail closed if upstream
# moves.  chmod lives in the SAME RUN as the clone so the tree is not copied
# into a second layer.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin 8a5946ed6bce34bfeb26b964fc8875447d841ae8 \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && chmod -R a+rwX /app/src

# ---- extract the upstream regression test, its asset, and the pristine
#      parent module, all from the FIX commit via a throwaway bare clone -------
# test_transforms_v2.py resolves an asset by Path(__file__) at module import,
# so the asset it loads at import time is extracted alongside.
RUN git init -q --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin 3cbf38e82f6d0e35cfa8363b165b5a372fcfbfff \
 && mkdir -p /opt/golden/assets \
 && git show 3cbf38e82f6d0e35cfa8363b165b5a372fcfbfff:test/test_transforms_v2.py \
      > /opt/golden/test_transforms_v2.py \
 && git show 3cbf38e82f6d0e35cfa8363b165b5a372fcfbfff:test/assets/gaussian_blur_opencv_results.pt \
      > /opt/golden/assets/gaussian_blur_opencv_results.pt \
 && cp /app/src/torchvision/transforms/v2/functional/_geometry.py \
      /opt/golden/parent_geometry.py \
 && test -s /opt/golden/test_transforms_v2.py \
 && test -s /opt/golden/assets/gaussian_blur_opencv_results.pt \
 && test -s /opt/golden/parent_geometry.py \
 && grep -q "test_kernel_bounding_boxes_at_canvas_boundary" /opt/golden/test_transforms_v2.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- python env: era-appropriate pinned CPU wheels, pytest from PyPI -------
ENV PATH=/opt/venv/bin:$PATH \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN python3 -m venv /opt/venv \
 && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu \
      'torch==2.14.0+cpu' 'torchvision==0.29.0+cpu'

RUN pip install --no-cache-dir 'pytest==8.4.2'

# ---- neutralize the torch 2.14 jit.script deprecation FutureWarning ---------
# The pinned release deprecates torch.jit.script with a FutureWarning; the
# era's test module runs with warnings as errors (pytestmark
# filterwarnings("error")), so without this the project's own kernel tests
# cannot run at all.  Remove only that warning; nothing else in torch changes.
RUN /opt/venv/bin/python - <<'PYEOF'
p = "/opt/venv/lib/python3.12/site-packages/torch/jit/_script.py"
s = open(p).read()
old = '''    if sys.version_info >= (3, 14):
        warnings.warn(
            "`torch.jit.script` is not supported in Python 3.14+ and may break. "
            "Please switch to `torch.compile` or `torch.export`.",
            FutureWarning,
        )
    else:
        warnings.warn(
            "`torch.jit.script` is deprecated. Please switch to `torch.compile` or `torch.export`.",
            FutureWarning,
        )
'''
new = '''    if sys.version_info >= (3, 14):
        pass
    else:
        pass
'''
assert old in s, "unexpected torch jit/_script.py bytes"
open(p, "w").write(s.replace(old, new))
print("patched torch jit deprecation warning")
PYEOF

# ---- wire the running code to the deliverable ------------------------------
# Overlay the checkout's transforms/v2 (era-matched) on the wheel, then symlink
# functional/_geometry.py so the executed code IS the checked-out tree that the
# agent edits.  Verify import + linkage + the bug at build time.
RUN SP=$(/opt/venv/bin/python -c 'import sysconfig; print(sysconfig.get_path("purelib"))') \
 && test -d "$SP/torchvision" \
 && cp -f /app/src/torchvision/transforms/v2/*.py \
           "$SP/torchvision/transforms/v2/" \
 && cp -f /app/src/torchvision/transforms/v2/functional/*.py \
           "$SP/torchvision/transforms/v2/functional/" \
 && rm -rf "$SP/torchvision/transforms/v2/__pycache__" \
 && rm -rf "$SP/torchvision/transforms/v2/functional/__pycache__" \
 && rm -f "$SP/torchvision/transforms/v2/functional/_geometry.py" \
 && ln -s /app/src/torchvision/transforms/v2/functional/_geometry.py \
           "$SP/torchvision/transforms/v2/functional/_geometry.py" \
 && test "$(readlink "$SP/torchvision/transforms/v2/functional/_geometry.py")" = "/app/src/torchvision/transforms/v2/functional/_geometry.py" \
 && PYTHONDONTWRITEBYTECODE=1 /opt/venv/bin/python - <<'PYEOF'
import os
import torch, torchvision
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F
import torchvision.transforms.v2.functional._geometry as geom
assert torch.__version__ == "2.14.0+cpu", torch.__version__
assert torchvision.__version__.startswith("0.29.0"), torchvision.__version__
assert os.path.realpath(geom.__file__) == "/app/src/torchvision/transforms/v2/functional/_geometry.py", geom.__file__
H, W = 64, 76
bbox = torch.tensor([[0.0, 0.0, float(W), float(H)]])
disp = torch.zeros((1, H, W, 2))
try:
    F.elastic_bounding_boxes(bbox, format=tv_tensors.BoundingBoxFormat.XYXY, canvas_size=(H, W), displacement=disp)
    raise SystemExit("FAIL: no error at parent (bug does not reproduce)")
except IndexError as e:
    assert "index 76 is out of bounds" in str(e), e
    print("parent bug reproduces:", e)
print("build-time check OK: torch", torch.__version__, "torchvision", torchvision.__version__)
PYEOF

# ---- ship the user-facing helpers, keep everything writable for uid 1000 ----
WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app && chmod +x /app/run_pytest.sh

CMD ["/bin/bash"]