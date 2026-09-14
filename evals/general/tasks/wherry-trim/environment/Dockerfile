# wherry-trim: scikit-image/scikit-image #7496
# The RANSAC max-trials budget (_dynamic_max_trials in skimage/measure/fit.py)
# returns a non-positive count (-0.0) when the stopping probability is so small
# that (1 - probability) rounds to exactly 1.0, or the denominator does.
#
# The agent receives the real upstream tree at the PARENT commit, must author
# its own failing reproduction, then diagnose and repair the single Python
# file. The fix is pure Python, so the editable install reflects the agent's
# edit immediately; nothing needs recompiling in the trial.
ARG UPSTREAM_SHA=f1892afb76e60b6fe41cf0c73be97f918581aa33
ARG UPSTREAM_FIX=137dbfb5f1e597cf4cb069486319d7defdd1077e

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG UPSTREAM_FIX

# 1 CPU: keep the numeric thread pools at 1 as the suite-wide convention.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Dependency pins from the mining entry, resolved against this base's
# interpreter (measured versions of the throwaway build).
RUN pip install --no-cache-dir \
      'numpy==2.1.3' 'scipy==1.14.1' 'Cython==3.0.12' \
      'meson-python==0.21.1' 'ninja==1.13.2' 'pythran==0.19.0' \
      'lazy-loader==0.5' 'packaging==26.3' 'networkx==3.6.1' \
      'pillow==12.3.0' 'imageio==2.37.4' 'tifffile==2026.9.9' \
      'matplotlib==3.11.2' \
      'pytest==9.1.1' 'pytest-cov==7.1.0' 'pytest-faulthandler==2.0.1' \
      'pytest-doctestplus==1.7.1' 'pytest-localserver==0.10.0' \
      'pooch==1.9.0' 'asv==0.6.6' 'numpydoc==1.10.0'

# Clone the REAL upstream repository at exactly the parent commit, as the
# shallowest possible clone: one depth-1 fetch of the pinned SHA means the
# object store in /app/src holds ONLY the parent commit. The fix commit is
# NEVER fetched into this clone; it is asserted unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scikit-image/scikit-image.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Warm editable install (~90 s on one core) so the trial never compiles and a
# pure-Python edit to a source file takes effect immediately. Fail closed if
# the build dirties the tracked tree (build/ and __pycache__ are gitignored).
RUN cd /app/src && pip install -e . --no-build-isolation \
      --config-settings=setup-args=-Dcpp_std=c++17 \
 > /tmp/editable-install.log 2>&1; rc=$?; \
    tail -3 /tmp/editable-install.log; \
    if [ $rc -ne 0 ]; then echo "EDITABLE INSTALL FAILED (exit $rc)"; exit 1; fi; \
    test -z "$(git status --porcelain)" \
 && echo "editable install ok, working tree clean"

# Parent-direction confirmation 1/2 IN THIS IMAGE: the direct reproduction.
# The private budget helper must return a NON-positive count for the reported
# pathological input, exactly as mined/verified; if the bug does not reproduce
# with these pins the task would be unpassable, so fail the build.
RUN python3 - <<'PY'
import math
from skimage.measure.fit import _dynamic_max_trials as f
r = f(1, 100, 1000, 1e-40)
print("parent repro (1,100,1000,1e-40):", repr(r))
assert not (r > 0), "bug does not reproduce: budget is positive at parent"
assert math.copysign(1.0, float(r)) < 0, "expected -0.0 (negative zero), got %r" % r
assert not (f(1, 100, 10, 1e-40) > 0)
print("parent reproduction confirmed: non-positive budget")
PY

# Parent-direction confirmation 2/2: the project's own existing
# robust-fitting test module passes at the parent (30 tests). This is the
# suite the verifier requires to stay green after the agent's repair.
RUN cd /app/src && python3 -m pytest skimage/measure/tests/test_fit.py \
      -p no:cacheprovider -q > /tmp/parent-tests.log 2>&1; rc=$?; \
    tail -3 /tmp/parent-tests.log; \
    if [ $rc -ne 0 ]; then echo "PARENT TEST SUITE FAILED (exit $rc)"; exit 1; fi; \
    grep -q "30 passed" /tmp/parent-tests.log \
 || { echo "test_fit.py did not report 30 passed at parent"; exit 1; }

# Bake a PRISTINE PRE-FIX copy of the whole importable package at /opt/prefix:
# every .py from the parent source tree merged with the compiled .so from the
# meson build tree, and fit.py byte-identical to the parent blob. The verifier
# runs the agent's own reproduction against this copy (via `python3 -S` +
# PYTHONPATH, which disables the editable meta-finder) and requires it to
# FAIL, proving the symptom is real and the reproduction targets it.
RUN mkdir -p /opt/prefix/skimage \
 && (cd /app/src/skimage && tar cf - .) \
      | (cd /opt/prefix/skimage && tar xf -) \
 && (cd /app/src/build/cp312/skimage \
      && find . -type f -name "*.so" | while read f; do \
           mkdir -p "/opt/prefix/skimage/$(dirname "$f")"; \
           cp "$f" "/opt/prefix/skimage/$f"; \
         done) \
 && git -C /app/src show ${UPSTREAM_SHA}:skimage/measure/fit.py \
      > /opt/prefix/skimage/measure/fit.py \
 && test "$(find /opt/prefix/skimage -name '*.so' | wc -l)" -ge 50 \
 && cd /tmp \
 && PYTHONPATH=/opt/prefix:/usr/local/lib/python3.12/site-packages \
      python3 -S -c "import skimage.measure.fit as fit_mod; print('pristine fit:', fit_mod.__file__); r=fit_mod._dynamic_max_trials(1,100,1000,1e-40); print('pristine repro:', repr(r)); assert not (r > 0)" \
 && echo "pristine pre-fix copy bakes and reproduces the bug"

# Extract the project's own regression test for this bug (the fix commit's
# test_fit.py, which renames the old 'denom nearly 1' test to
# test_ransac_dynamic_max_trials_clipping and adds the (1-probability)~1
# assertions) into /opt/golden using a THROWAWAY clone that is deleted
# immediately afterwards, so the fix commit never lands in /app/src and no
# upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/scikit-image/scikit-image.git \
 && git fetch --depth 1 origin ${UPSTREAM_FIX} >/dev/null 2>&1 \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_FIX}:skimage/measure/tests/test_fit.py \
      > /opt/golden/test_fit.py \
 && test -s /opt/golden/test_fit.py \
 && grep -q "def test_ransac_dynamic_max_trials_clipping" /opt/golden/test_fit.py \
 && ! grep -q "def test_ransac_dynamic_max_trials_denom_nearly_1" /opt/golden/test_fit.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && test ! -e /tmp/upstream-fix-clone \
 && echo "golden test extracted; throwaway clone removed"

# Belt: the fix commit and its contents are unreachable from the trial clone,
# and the object store holds exactly one commit. If the pin ever moves, or a
# later edit fetches the fix into /app/src, the build fails closed.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git rev-parse --verify HEAD^{commit})" = "${UPSTREAM_SHA}" \
 && test "$(git rev-list --count HEAD)" = 1 \
 && echo "fix commit unreachable from trial clone; object store has exactly 1 commit"

# Record sha256 pins of the golden test, of the pristine pre-fix fit.py, and
# of the interpreter/test-toolchain, so the verifier can detect substitution.
# /opt is read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_fit.py > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/skimage/measure/fit.py > /opt/pins/prefix-fit.sha256 \
 && sha256sum /usr/local/bin/python3.12 /usr/local/bin/python3 \
              /usr/local/bin/pytest \
              /usr/local/lib/python3.12/site-packages/_scikit_image_editable_loader.py \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/golden /opt/prefix /opt/pins \
 && find /opt/golden /opt/prefix /opt/pins -type f -exec chmod 444 {} + \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-fit.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + pristine fit.py + toolchain pinned"

# Final permissions: every writable path must be usable by root and by uid
# 1000 alike (caches, pycache, the editable source tree).
RUN mkdir -p /app && chmod -R a+rwX /app/src /tmp /app \
 && rm -f /tmp/*.log /tmp/parent-tests.log /tmp/editable-install.log 2>/dev/null; \
    chmod a+rwx /tmp

COPY files/ /app/

WORKDIR /app
CMD ["/bin/bash"]