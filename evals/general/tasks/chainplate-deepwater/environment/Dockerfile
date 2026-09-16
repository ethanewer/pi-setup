# chainplate-deepwater: pytorch/vision integer bounding-box conversion bugfix.
#
# Clones the REAL upstream repository at the pinned PARENT commit (the bug is
# live there), creates the pinned-dependency venv with the commit-era
# transforms/v2 and tv_tensors Python modules overlaid from the checkout (the
# released wheel predates the commit era and cannot import the project's own
# test modules), extracts the project's own regression test from the FIX
# commit into /opt/golden via a throwaway clone (so upstream bytes never land
# in the task tree and the fix commit never lands in /app/src), and
# re-confirms BOTH directions inside this image: the upstream regression test
# and the direct reproducer must FAIL on the parent tree and PASS on the fixed
# tree.

ARG UPSTREAM_SHA_PARENT=6940e19087cecb5108370703e207f7a33d9b478d
ARG UPSTREAM_SHA_FIX=74d128539ddf17c58a955468abe85e062c293ed9

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The whole trial is offline after build time. cpus=1: keep the numeric thread
# pools pinned to a single core so torch never oversubscribes the one vCPU.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    TZ=UTC

# 1) Pinned dependency venv. torch/torchvision come from the pytorch CPU wheel
#    index (the versions the bug lives in); pytest from PyPI. The torchvision
#    wheel predates the pinned commit, so its Python modules will be replaced
#    by the checkout's own bytes in step 3.
RUN python3 -m venv /app/env \
 && /app/env/bin/pip install --no-cache-dir 'torch==2.10.0+cpu' 'torchvision==0.25.0+cpu' \
        --index-url https://download.pytorch.org/whl/cpu \
        --extra-index-url https://pypi.org/simple \
 && /app/env/bin/pip install --no-cache-dir 'pytest==8.4.2' \
 && /app/env/bin/python -c "import torch, torchvision, pytest; print('torch', torch.__version__, 'torchvision', torchvision.__version__, 'pytest', pytest.__version__)"

# 2) Clone the REAL upstream repository at exactly the parent commit, with the
#    shallowest possible history: `git init` + one depth-1 fetch of the pinned
#    SHA means the object store in /app/src holds ONLY the parent commit. The
#    fix commit (which the agent must not be able to look up or fetch) is never
#    fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && test -z "$(git status --porcelain)" \
 && echo "cloned pytorch/vision at parent ${UPSTREAM_SHA_PARENT}"

# 3) Overlay: the installed torchvision must run the exact code of the pinned
#    commit. The commit-era transforms/v2 and tv_tensors modules are pure
#    Python and replace the wheel's own copies wholesale (the commit era added
#    cvcuda-era names that the project's own test modules import, and the
#    wheel predates them). The venv package mirrors /app/src from here on, and
#    that mirror is part of the task contract.
RUN TREE=/app/src/torchvision \
 && SP=/app/env/lib/python3.12/site-packages/torchvision \
 && rm -rf "$SP/transforms/v2" "$SP/tv_tensors" \
 && cp -r "$TREE/transforms/v2" "$SP/transforms/" \
 && cp -r "$TREE/tv_tensors" "$SP/" \
 && grep -Fq 'rounding_mode=None if cxcywh.is_floating_point() else' "$SP/transforms/v2/functional/_meta.py" \
 && ! grep -Fq 'half_wh = cxcywh[..., 2:] / 2' "$SP/transforms/v2/functional/_meta.py" \
 && grep -q 'def cvcuda_to_tensor' "$SP/transforms/v2/functional/_type_conversion.py" \
 && echo "commit-era (parent) transforms/v2 + tv_tensors overlays active in venv"

# 4) Extract the project's own regression test for this bug (the fix-commit
#    test file, which differs from the parent's only by the added
#    test_cxcywh_to_xyxy_odd_dimensions method) into /opt/golden, and the
#    FIXED main module into /tmp (used only to re-confirm the fix direction),
#    using a THROWAWAY clone that is deleted immediately afterwards, so
#    upstream test bytes never land in this task tree and the fix commit never
#    lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/pytorch/vision.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:test/test_transforms_v2.py > /opt/golden/test_transforms_v2.py \
 && test -s /opt/golden/test_transforms_v2.py \
 && test "$(git hash-object /opt/golden/test_transforms_v2.py)" = "9dd758d9595d7d9912c463a87f5c7935c7191de0" \
 && grep -q "test_cxcywh_to_xyxy_odd_dimensions" /opt/golden/test_transforms_v2.py \
 && git show ${UPSTREAM_SHA_FIX}:torchvision/transforms/v2/functional/_meta.py > /tmp/_meta.fixed.py \
 && test -s /tmp/_meta.fixed.py \
 && grep -Fq 'half_wh = cxcywh[..., 2:] / 2' /tmp/_meta.fixed.py \
 && echo "golden regression test extracted from fix commit ${UPSTREAM_SHA_FIX}" \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000. Give
# uid 1000 ownership of the tree, the venv and /opt so every writable path is
# writable, and make the pinned git repo safe for any user.
WORKDIR /app
RUN chmod -R a+rwX /app/env /app/src /opt 2>/dev/null || true \
 && chown -R 1000:1000 /app/env /app/src 2>/dev/null || true \
 && mkdir -p /opt/golden /opt && chmod a+rwx /opt

# The direct reproducer used everywhere in this image (and by the trial).
COPY files/repro.py /opt/repro.py
RUN test "$(git hash-object /opt/repro.py)" = "74852604b35973747bf7ceab612ecc21a528f578" \
 && chmod a+r /opt/repro.py

# 5) Direction 1 (PARENT): plant the upstream regression test into the tree and
#    run it. It MUST FAIL here -- if it passes, this image does not reproduce
#    the bug and the task cannot work. The direct reproducer must also fail
#    with the negative top edge. pytest runs from a neutral CWD with an
#    absolute test path so `import torchvision` resolves to the venv package
#    (running from /app/src would put the un-built source tree on sys.path).
RUN cp /opt/golden/test_transforms_v2.py /app/src/test/test_transforms_v2.py \
 && find /app/env/lib/python3.12/site-packages/torchvision -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true \
 && cd /tmp \
 && /app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
        -k test_cxcywh_to_xyxy_odd_dimensions -p no:cacheprovider -o addopts='' \
        --tb=line > /tmp/dir1.log 2>&1; rc=$?; \
    echo "=== parent-direction upstream regression rc=$rc (expected non-zero) ==="; \
    tail -10 /tmp/dir1.log; \
    if [ $rc -eq 0 ]; then echo "ERROR: upstream regression PASSED on the parent tree"; exit 1; fi; \
    grep -qE "1 failed" /tmp/dir1.log || { echo "ERROR: expected '1 failed' summary at parent"; exit 1; }; \
    /app/env/bin/python /opt/repro.py > /tmp/dir1-repro.log 2>&1; rc2=$?; \
    echo "=== parent-direction direct repro rc=$rc2 (expected non-zero) ==="; \
    tail -3 /tmp/dir1-repro.log; \
    if [ $rc2 -eq 0 ]; then echo "ERROR: direct repro PASSED at parent; bug not live"; exit 1; fi; \
    grep -q -- "-1" /tmp/dir1-repro.log || { echo "ERROR: expected the negative coordinate in repro output"; exit 1; }

# 6) Direction 2 (FIX): overlay the fixed module exactly as a solver would,
#    into BOTH the checkout and the venv mirror. The upstream regression test
#    must pass, the whole TestConvertBoundingBoxFormat class (the project's own
#    existing suite around this code, reference-checked against
#    torchvision.ops.box_convert) must pass, and the direct reproducer must
#    print OK.
RUN cp /tmp/_meta.fixed.py /app/src/torchvision/transforms/v2/functional/_meta.py \
 && cp /tmp/_meta.fixed.py /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_meta.py \
 && find /app/env/lib/python3.12/site-packages/torchvision -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true \
 && /app/env/bin/python /opt/repro.py > /tmp/dir2-repro.log 2>&1; rc=$?; \
    echo "=== fix-direction direct repro rc=$rc (expected 0) ==="; \
    tail -3 /tmp/dir2-repro.log; \
    if [ $rc -ne 0 ]; then echo "ERROR: direct repro FAILED on fixed tree"; exit 1; fi; \
    grep -q "^OK$" /tmp/dir2-repro.log || { echo "ERROR: repro did not print OK"; exit 1; }; \
    cd /tmp \
 && /app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
        -k test_cxcywh_to_xyxy_odd_dimensions -p no:cacheprovider -o addopts='' \
        --tb=line > /tmp/dir2-golden.log 2>&1; rc=$?; \
    echo "=== fix-direction upstream regression rc=$rc (expected 0) ==="; \
    tail -8 /tmp/dir2-golden.log; \
    if [ $rc -ne 0 ]; then echo "ERROR: upstream regression FAILED on fixed tree"; exit 1; fi; \
    grep -qE "1 passed" /tmp/dir2-golden.log || { echo "ERROR: expected '1 passed' summary at fix"; exit 1; }

# 7) Fix-direction full class run: the project's own TestConvertBoundingBoxFormat
#    suite must stay green with the fix in place (proves the change broke
#    nothing else around this code path).
RUN cd /tmp \
 && /app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
        -k "TestConvertBoundingBoxFormat" -p no:cacheprovider -o addopts='' \
        --tb=short -q > /tmp/dir2-class.log 2>&1; rc=$?; \
    echo "=== fix-direction TestConvertBoundingBoxFormat rc=$rc (expected 0) ==="; \
    tail -8 /tmp/dir2-class.log; \
    if [ $rc -ne 0 ]; then echo "ERROR: TestConvertBoundingBoxFormat FAILED on fixed tree"; exit 1; fi; \
    grep -qE "passed" /tmp/dir2-class.log || { echo "ERROR: no pytest summary in class run"; exit 1; }

# 8) Restore the pristine parent state: the trial must start from EXACT parent
#    bytes (no planted test, no applied fix), in the checkout AND in the venv
#    mirror, with every bytecode cache that could carry fix-direction state
#    purged from both trees.
RUN cd /app/src \
 && git restore --worktree --source=HEAD -- \
        torchvision/transforms/v2/functional/_meta.py \
        test/test_transforms_v2.py \
 && cp /app/src/torchvision/transforms/v2/functional/_meta.py \
        /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_meta.py \
 && find /app/env/lib/python3.12/site-packages/torchvision /app/src -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true \
 && rm -rf /app/src/.pytest_cache \
 && test -z "$(git status --porcelain)" \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && grep -Fq 'rounding_mode=None if cxcywh.is_floating_point() else' \
        /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_meta.py \
 && echo "tree restored to pristine parent bytes; venv mirror restored to parent"

COPY files/ /app/
RUN chmod a+rwX /app
WORKDIR /app
CMD ["/bin/bash"]