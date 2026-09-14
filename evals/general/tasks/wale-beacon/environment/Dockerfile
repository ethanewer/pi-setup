# wale-beacon: upstream-clone debugging task on pytorch/vision (issue #9615 family).
#
# The trial container gets the REAL upstream tree at the pinned parent commit
# (/app/src, shallow, single-commit object store), a venv with the official CPU
# wheels (the compiled JPEG codec lives in the wheel; the pure-Python transform
# logic of the installed torchvision resolves to the /app/src tree through a
# symlink, so a fix made in the tree is the fix that runs), a pristine pre-fix
# copy of the buggy module at /opt/prefix, sha256 trust anchors at /opt/pins,
# and the upstream regression test for this bug extracted at /opt/golden from a
# THROWAWAY clone of the FIX commit that is deleted before the layer ends (the
# fix object NEVER enters /app/src).

FROM bench-base:python-3.12

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONUNBUFFERED=1

ARG UPSTREAM_SHA_PARENT=c7ef957c29cadb0b5d053164bf5e763dfe49e829
ARG UPSTREAM_SHA_FIX=50237caaf648140f0029b16f748c578a364ff15a

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# 1) Real upstream repository at the pinned PARENT commit. `git init` + one
#    depth-1 fetch of the pinned SHA means the object store in /app/src holds
#    ONLY the parent commit (the fix commit is asserted unreachable later).
#    Ownership is fixed for uid 1000 in the SAME RUN that creates the tree, so
#    no layer copies the checkout a second time.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 --no-tags origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

# 2) venv with the pinned CPU wheels (the compiled JPEG encoder/decoder) plus
#    pytest, the project's own test runner. All ownership is fixed in this same
#    RUN.
RUN python3 -m venv /app/env \
 && /app/env/bin/pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu \
      'torch==2.14.0+cpu' 'torchvision==0.29.0+cpu' \
 && /app/env/bin/pip install --no-cache-dir 'pytest==8.3.4' \
 && /app/env/bin/python -c "import torch, torchvision; print('torch', torch.__version__, 'torchvision', torchvision.__version__)" \
 && chown -R 1000:1000 /app/env \
 && chmod -R a+rwX /app/env

# 3) The installed package's transform logic follows the /app/src tree. The
#    wheel's copy of the buggy module is replaced with a symlink to the tree's
#    file (the compiled image extension stays in the wheel). Then the mining
#    reproduction is confirmed in THIS image: against the parent file it must
#    FAIL with the stride/view RuntimeError.
RUN rel=torchvision/transforms/v2/functional/_augment.py \
 && site=/app/env/lib/python3.12/site-packages \
 && rm -f "$site/$rel" \
 && ln -s "/app/src/$rel" "$site/$rel" \
 && chown -h 1000:1000 "$site/$rel" \
 && cd /tmp && PYTHONDONTWRITEBYTECODE=1 /app/env/bin/python - <<'PY'
import sys, torch
from torchvision.transforms.v2 import functional as F
image = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)
assert not image.is_contiguous()
try:
    F.jpeg_image(image, quality=75)
except RuntimeError as e:
    msg = str(e)
    assert "view size is not compatible" in msg and "stride" in msg, msg
    print("PARENT DIRECTION: reproduction raises:", msg[:80])
    sys.exit(0)
print("REPRO DID NOT RAISE at parent - FAILING CLOSED")
sys.exit(1)
PY

# 4) Pristine pre-fix module bytes baked at /opt/prefix (used by the verifier to
#    run the agent's reproduction and the hidden cases against the pre-fix tree
#    concept) plus the first trust anchors.
RUN mkdir -p /opt/prefix \
 && cp /app/src/torchvision/transforms/v2/functional/_augment.py /opt/prefix/_augment.py \
 && cd /app/src \
 && test "$(git hash-object /opt/prefix/_augment.py)" = "$(git rev-parse ${UPSTREAM_SHA_PARENT}:torchvision/transforms/v2/functional/_augment.py)" \
 && grep -q "image = image.view" /opt/prefix/_augment.py \
 && chmod 444 /opt/prefix/_augment.py

# 5) Golden test and fix-direction confirmations. The project's own regression
#    test for this bug is extracted from the FIX commit via a THROWAWAY clone
#    under /tmp that is deleted before the layer ends; the fix-commit bytes are
#    used only for the build-time fix-direction confirmations and are never left
#    in the image. The golden runner is built from the upstream test's own
#    method body, verbatim.
RUN rel=torchvision/transforms/v2/functional/_augment.py \
 && site=/app/env/lib/python3.12/site-packages \
 && sitep="$site/torchvision/transforms/v2/functional" \
 && git init -q /tmp/fixclone \
 && cd /tmp/fixclone \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 --no-tags origin ${UPSTREAM_SHA_FIX} >/dev/null 2>&1 \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && git show ${UPSTREAM_SHA_FIX}:test/test_transforms_v2.py \
      | awk '/^    def test_kernel_non_contiguous_leading_dimensions/{p=1} p && /^    @pytest/{p=0} p{print}' \
      > /tmp/golden_method.txt \
 && test -s /tmp/golden_method.txt \
 && grep -q "def test_kernel_non_contiguous_leading_dimensions" /tmp/golden_method.txt \
 && git show ${UPSTREAM_SHA_FIX}:${rel} > /tmp/fix_augment.py \
 && grep -q "image = image.reshape" /tmp/fix_augment.py \
 && ! grep -q "image = image.view" /tmp/fix_augment.py \
 && mkdir -p /opt/golden \
 && printf '%s\n' 'import torch' 'from torch.testing import assert_close' 'from torchvision.transforms.v2 import functional as F' '' 'def assert_equal(actual, expected):' '    assert_close(actual, expected, rtol=0, atol=0)' '' 'class TestJPEG:' '' > /opt/golden/test_kernel_non_contiguous_leading_dimensions.py \
 && sed 's/^/    /' /tmp/golden_method.txt >> /opt/golden/test_kernel_non_contiguous_leading_dimensions.py \
 && grep -q "def test_kernel_non_contiguous_leading_dimensions" /opt/golden/test_kernel_non_contiguous_leading_dimensions.py

# 5b) Build-time confirmations, both directions, in THIS image.
#      FIX direction first: overlay the fix-commit module byte-for-byte, then the
#      direct reproduction, the golden test and the hidden-case equivalents must
#      all PASS, and the project's own existing JPEG tests must stay green.
RUN rel=torchvision/transforms/v2/functional/_augment.py \
 && site=/app/env/lib/python3.12/site-packages \
 && sitep="$site/torchvision/transforms/v2/functional" \
 && rm -f "$sitep/_augment.py" && cp /tmp/fix_augment.py "$sitep/_augment.py" \
 && rm -rf "$sitep/__pycache__" \
 && chmod 644 "$sitep/_augment.py" \
 && cd /tmp \
 && /app/env/bin/python - <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
image = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)
assert not image.is_contiguous()
out = F.jpeg_image(image, quality=75)
assert torch.equal(out, F.jpeg_image(image.contiguous(), quality=75))
print("FIX DIRECTION: direct reproduction OK")
PY

RUN cd /tmp \
 && /app/env/bin/python -m pytest /opt/golden/test_kernel_non_contiguous_leading_dimensions.py -p no:cacheprovider -q 2>&1 | grep -q "1 passed"

RUN cd /tmp \
 && /app/env/bin/python - <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
cases = [
    ("h1 video transpose", F.jpeg_video, torch.randint(0, 256, (2, 5, 3, 16, 16), dtype=torch.uint8).transpose(0, 1), 90),
    ("h2 step-sliced batch", F.jpeg_image, torch.randint(0, 256, (6, 4, 3, 16, 16), dtype=torch.uint8)[::2, ::2], 50),
    ("h3 6-d transpose", F.jpeg_image, torch.randint(0, 256, (2, 3, 4, 3, 16, 16), dtype=torch.uint8).transpose(0, 2), 25),
]
for name, fn, t, q in cases:
    assert not t.is_contiguous(), name
    out = fn(t, quality=q)
    ref = fn(t.contiguous(), quality=q)
    assert out.shape == t.shape and out.dtype == t.dtype, name
    assert torch.equal(out, ref), name
    assert not torch.equal(out, t), ("output equals input", name)
    print("FIX DIRECTION hidden-equivalent", name, "OK")
noise = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)
assert not torch.equal(F.jpeg_image(noise, quality=5), F.jpeg_image(noise, quality=95))
print("FIX DIRECTION quality-matters OK")
PY

RUN cd /tmp \
 && /app/env/bin/python -m pytest \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_video" \
      -p no:cacheprovider -q 2>&1 | tail -1 | grep -q "5 passed" \
 && echo "FIX DIRECTION: golden + hidden-equivalents + existing suite all pass"

# 5c) Restore the symlink so the shipped image is buggy-at-parent again, then
#     re-confirm PARENT direction: direct reproduction and golden test must FAIL,
#     hidden-equivalents must FAIL, and the project's existing (contiguous)
#     JPEG tests must still pass.
RUN rel=torchvision/transforms/v2/functional/_augment.py \
 && site=/app/env/lib/python3.12/site-packages \
 && sitep="$site/torchvision/transforms/v2/functional" \
 && rm -f "$sitep/_augment.py" && ln -s "/app/src/$rel" "$sitep/_augment.py" \
 && chown -h 1000:1000 "$sitep/_augment.py" \
 && rm -rf "$sitep/__pycache__" \
 && cd /tmp \
 && /app/env/bin/python - <<'PY'
import sys, torch
from torchvision.transforms.v2 import functional as F
image = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)
try:
    F.jpeg_image(image, quality=75)
except RuntimeError as e:
    assert "view size is not compatible" in str(e)
    print("PARENT DIRECTION (final state): reproduction raises, as required")
    sys.exit(0)
print("REPRO DID NOT RAISE - FAILING CLOSED")
sys.exit(1)
PY

RUN cd /tmp \
 && sh -c '/app/env/bin/python -m pytest /opt/golden/test_kernel_non_contiguous_leading_dimensions.py -p no:cacheprovider -q >/tmp/golden-parent.out 2>&1; rc=$?; if [ $rc -eq 0 ]; then echo "GOLDEN PASSED AT PARENT - FAILING CLOSED"; exit 1; fi; echo "PARENT DIRECTION: golden test fails at parent (rc=$rc)"; exit 0'

RUN cd /tmp \
 && /app/env/bin/python - <<'PY'
import sys, torch
from torchvision.transforms.v2 import functional as F
cases = [
    (F.jpeg_video, torch.randint(0, 256, (2, 5, 3, 16, 16), dtype=torch.uint8).transpose(0, 1), 90),
    (F.jpeg_image, torch.randint(0, 256, (6, 4, 3, 16, 16), dtype=torch.uint8)[::2, ::2], 50),
    (F.jpeg_image, torch.randint(0, 256, (2, 3, 4, 3, 16, 16), dtype=torch.uint8).transpose(0, 2), 25),
]
ok = 0
for fn, t, q in cases:
    try:
        fn(t, quality=q)
        ok += 1
    except RuntimeError:
        pass
if ok:
    print("hidden-equivalent cases PASSED at parent - FAILING CLOSED")
    sys.exit(1)
print("PARENT DIRECTION: all hidden-equivalents raise, as required")
sys.exit(0)
PY

RUN cd /tmp \
 && /app/env/bin/python -m pytest \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_video" \
      -p no:cacheprovider -q 2>&1 | tail -1 | grep -q "5 passed" \
 && rm -rf /tmp/fixclone /tmp/fix_augment.py /tmp/golden_method.txt /tmp/golden-parent.out \
 && echo "PARENT DIRECTION: existing suite still green in shipped state"
# 6) Belt: the fix commit must not be reachable from the trial clone (the
#    object store holds exactly one commit), and HEAD must still be the pin.
#    Then record sha256 trust anchors: golden test, pre-fix module, the venv
#    python binary, and a manifest of every wheel file of the installed
#    torchvision package (minus the symlinked module replaced by the tree), so
#    the verifier can detect a planted stub that fakes the codec.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -L /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_augment.py \
 && mkdir -p /opt/pins \
 && cd /app/env/lib/python3.12/site-packages \
 && find torchvision -type f ! -path "*/functional/_augment.py" ! -path "*/__pycache__/*" \
      | sort | xargs sha256sum > /opt/pins/torchvision-site.sha256 \
 && sha256sum /opt/golden/test_kernel_non_contiguous_leading_dimensions.py > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/_augment.py > /opt/pins/prefix.sha256 \
 && sha256sum /app/env/bin/python > /opt/pins/python.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && find /opt/pins -type f -exec chmod 444 {} + \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix.sha256 >/dev/null \
 && sha256sum -c /opt/pins/python.sha256 >/dev/null \
 && echo "trust anchors recorded (golden, prefix, python, torchvision manifest)"

# 7) /app is created by the final COPY; every other path was already owned and
#    writable for both root and uid 1000 inside the RUN that created it.

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]