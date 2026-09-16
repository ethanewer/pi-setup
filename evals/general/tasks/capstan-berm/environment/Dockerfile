# capstan-berm: real scikit-image/scikit-image cloned at the PARENT of upstream
# fix ff3dd9468 ("Fix morphology.thin so input array is not modified", issue
# #7469). The agent gets the genuine buggy tree, must reproduce, localise and
# fix it, and is never told the issue, the commit, or the file to change. The
# fix commit is never fetched into /app/src; the project's own regression test
# is extracted into /opt/golden from a throwaway clone that is deleted
# immediately afterwards, so upstream test bytes never enter this task tree.
ARG UPSTREAM_SHA_PARENT=6baff20f0fe4c3bee859447f77f0014ec25f820b
ARG UPSTREAM_SHA_FIX=ff3dd9468bd10461363e1f7fdba9b12409fba216
ARG GOLDEN_SHA256=5edfb911e066f001e43a8adc284f4a5f8073f102c3cf8417d66ba16bb92bae70

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GOLDEN_SHA256

# The trial container runs on one vCPU; pin every numeric thread pool so the
# scipy/numpy code paths do not oversubscribe the core.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# bench-base:python-3.12 ships no C/C++ compiler; the scikit-image build needs
# one at image-build time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*

# Pinned dependency set (era-matched to the pinned commit; resolved against the
# base image's own interpreter). Everything the editable build and the project's
# own test runner need.
RUN pip install --no-cache-dir \
      numpy==2.1.3 \
      scipy==1.14.1 \
      Cython==3.0.11 \
      meson-python==0.17.1 \
      ninja==1.11.1.1 \
      pythran==0.19.0 \
      setuptools==75.6.0 \
      wheel==0.45.1 \
      packaging==24.2 \
      lazy-loader==0.4 \
      networkx==3.4.2 \
      pillow==11.0.0 \
      imageio==2.36.1 \
      tifffile==2024.9.20 \
      pooch==1.8.2 \
      pytest==8.3.5 \
      pytest-cov==5.0.0 \
      pytest-faulthandler==2.0.1 \
      pytest-doctestplus==1.2.1 \
      pytest-localserver==0.8.1 \
      numpydoc==1.8.0

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned SHA
# means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which an agent must not be able to look up or fetch) is never fetched
# into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scikit-image/scikit-image.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (test_skeletonize.py
# exactly as it exists at the fix commit: the parent's file plus
# TestThin::test_thin_copies_input) into /opt/golden using a THROWAWAY clone
# that is deleted immediately afterwards, so upstream test bytes never land in
# this task tree and the fix commit never lands in /app/src. A pinned sha256 of
# the extracted bytes lets the verifier detect tampering later.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/scikit-image/scikit-image.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:skimage/morphology/tests/test_skeletonize.py \
      > /opt/golden/test_skeletonize.py \
 && test "$(sha256sum /opt/golden/test_skeletonize.py | cut -d' ' -f1)" = "${GOLDEN_SHA256}" \
 && grep -q "test_thin_copies_input" /opt/golden/test_skeletonize.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone, and that
# the object store holds nothing beyond the single parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list HEAD --count)" = "1" \
 && test "$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)" = "0"

# Editable install: the compiled extensions (Cython/pythran) are built once
# here into the environment; the pure-Python modules import from /app/src, so
# an edit to the plain .py sources is picked up immediately, offline. The
# -Dcpp_std=c++17 setup arg is mandatory with pythran>=0.19 (the tree's own
# cpp_std=c++14 fails to compile modern pythran headers).
RUN cd /app/src \
 && pip install -e . --no-build-isolation \
      --config-settings=setup-args=-Dcpp_std=c++17

# Re-confirm BOTH directions inside this very image, then restore the pristine
# parent tree. (The mining container proved them already; this proves them
# under THIS image's pinned dependency set, so the oracle reward is real.)
#   parent direction: the input array IS modified, and the project's own
#   regression test THIN COPIES INPUT fails (1 failed, 2 passed).
#   fix direction:    after the one-line copy fix the repro says
#   input_modified: False and the whole golden test file passes.
RUN cd /app/src \
 && cp /opt/golden/test_skeletonize.py skimage/morphology/tests/test_skeletonize.py \
 && python -c "import numpy as np; from skimage.morphology import thin; img=np.zeros((10,10),dtype=bool); img[2:8,2:8]=1; orig=img.copy(); thin(img); print('parent input_modified:', not np.array_equal(img, orig))" \
 ; python -m pytest -p no:cacheprovider -q \
      skimage/morphology/tests/test_skeletonize.py::TestThin::test_thin_copies_input \
    > /tmp/parent_direction.log 2>&1; echo "parent-direction pytest rc=$?"; tail -8 /tmp/parent_direction.log; \
  sed -i 's/^    skel = np.asanyarray(image, dtype=bool).view(np.uint8)/    skel = np.asanyarray(image, dtype=bool).copy().view(np.uint8)/' \
      skimage/morphology/_skeletonize.py \
 && grep -n "skel = np.asanyarray" skimage/morphology/_skeletonize.py | head -2 \
 && python -c "import numpy as np; from skimage.morphology import thin; img=np.zeros((10,10),dtype=bool); img[2:8,2:8]=1; orig=img.copy(); thin(img); print('fix input_modified:', not np.array_equal(img, orig)); import skimage.morphology._skeletonize as m; print('mod file:', m.__file__)" \
 ; python -m pytest -p no:cacheprovider -q \
      skimage/morphology/tests/test_skeletonize.py > /tmp/fix_direction.log 2>&1; echo "fix-direction pytest rc=$?"; tail -8 /tmp/fix_direction.log; \
  git checkout -- skimage/morphology/tests/test_skeletonize.py skimage/morphology/_skeletonize.py \
 && test "$(git status --porcelain | wc -l)" = "0" \
 && rm -f /tmp/parent_direction.log /tmp/fix_direction.log

# The tree is kept writable for whatever uid (root or 1000) the trial runs as;
# the __pycache__ caches generated at build time belong to root and are left
# ignored by the repo's .gitignore.
RUN find /app -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null; \
    chmod -R a+rwX /app \
 && chmod -R a+rwX /app/src

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]