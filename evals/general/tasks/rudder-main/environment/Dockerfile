# rudder-main: statsmodels OLS/WLS fixed-scale bug (issue #8190).
# The image clones the REAL upstream statsmodels/statsmodels tree and checks
# out the PARENT commit c67d83dc9, editable-installs it warm, and runs the
# both-directions confirmations at build time. The upstream FIX commit
# (3c7f8f811) is never fetched into /app/src; the golden regression test is
# extracted from it through a separate throwaway clone under /tmp that is
# deleted immediately afterwards, so the fix bytes never reach the trial
# tree or this task tree.
ARG UPSTREAM_SHA_PARENT=c67d83dc9befc8927753c207e3571443b42cc749
ARG UPSTREAM_SHA_FIX=3c7f8f8118160379e880d9d437d22edbb7ef9a9b

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=0

# uid 1000 worker for build-time confirmation steps and the trial.
RUN useradd -m -u 1000 worker

# Toolchain. git is needed by the build-time clone, the provenance checks,
# and the golden-test planting; gcc/g++ are build deps of the statsmodels
# Cython extensions.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc g++ git \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Python dependency pins (resolved against bench-base:python-3.12's own
# interpreter and index by the mining run; re-verified here on 2026-09-13).
RUN pip install --no-cache-dir \
      numpy==2.5.3 scipy==1.18.1 pandas==3.0.5 patsy==1.0.3 formulaic==1.2.2 \
      packaging==26.3 pytest==9.1.1 meson-python==0.21.1 meson==1.12.0 \
      ninja==1.13.2 cython==3.3.0 setuptools_scm==10.2.3 \
 && python -c "import numpy, scipy, pandas, patsy, formulaic; \
               print('deps', numpy.__version__, scipy.__version__, pandas.__version__)"

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: one depth-1 fetch of the pinned SHA, so the
# object store in /app/src holds ONLY the parent commit. Fail closed if the
# pin moves upstream.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/statsmodels/statsmodels.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /app/src

# Warm editable install (~40 s on one core; measured). The build output goes
# to /app/src/build (gitignored, working tree stays clean). The chown runs
# in the SAME layer so ownership changes cost nothing extra on disk.
RUN cd /app/src \
 && pip install -e . --no-build-isolation > /tmp/editable.log 2>&1; rc=$?; \
    tail -4 /tmp/editable.log; \
    if [ $rc -ne 0 ]; then echo "EDITABLE INSTALL FAILED (exit $rc)"; exit 1; fi \
 && chown -R 1000:1000 /app/src \
 && git status --porcelain | grep -q . \
    && { echo "editable install dirtied the tree"; exit 1; } || true \
 && echo "editable install ok, working tree clean"

# Everything below runs as uid 1000 (the same user the trial may run as),
# so every writable path is owned by uid 1000 from the start.
# ---------------------------------------------------------------------------
# 1) Parent-direction confirmation IN THIS IMAGE: the exact mined reproduction
#    must FAIL at the parent commit with the wrong .scale (the bug must be
#    present in this image, not just in the mining container).
RUN cat > /tmp/check_parent.py <<'EOF'
import numpy as np
np.random.seed(0)
from statsmodels.regression.linear_model import OLS
from statsmodels.tools.tools import add_constant
X = add_constant(np.random.rand(50, 2))
y = np.dot(X, [1, 2, 3]) + np.random.randn(50)
scale = 5.0
res = OLS(y, X).fit(cov_type="fixed scale", cov_kwds={"scale": scale})
import numpy.testing as npt
try:
    npt.assert_allclose(res.scale, scale)
except AssertionError:
    print("parent-direction OK: res.scale = %.9f != supplied %.1f"
          % (float(res.scale), scale))
    raise SystemExit(0)
print("BUG NOT REPRODUCED at parent: res.scale == %.9f" % float(res.scale))
raise SystemExit(1)
EOF
RUN su -s /bin/bash worker -c 'export PATH=/usr/local/bin:$PATH; python /tmp/check_parent.py' \
 && rm -f /tmp/check_parent.py

# 2) Bake a pristine PRE-FIX statsmodels/regression/linear_model.py (the
#    parent blob) at /opt/prefix, with its sha256. The verifier swaps this
#    file into the tree to prove the agent's reproduction targets the real
#    symptom (repro must fail on the pre-fix module and pass on the repair).
RUN mkdir -p /opt/prefix \
 && cp /app/src/statsmodels/regression/linear_model.py /opt/prefix/linear_model_parent.py \
 && test -s /opt/prefix/linear_model_parent.py \
 && chmod 555 /opt/prefix \
 && chmod 444 /opt/prefix/linear_model_parent.py

# 3) Extract the project's own regression test for this bug (the test
#    test_ols_wls_fixed_scale that the fix commit appends to
#    statsmodels/regression/tests/test_regression.py) into /opt/golden using
#    a THROWAWAY clone in /tmp that is deleted immediately afterwards, so the
#    fix commit object never enters the shipped repository. The extracted
#    file is the fix commit's whole test_regression.py, which is a strict
#    superset of the parent's (verified: the two differ only by the appended
#    golden test). This RUN only touches /tmp and /opt, never /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/statsmodels/statsmodels.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:statsmodels/regression/tests/test_regression.py \
        > /opt/golden/test_regression.py \
 && grep -q "def test_ols_wls_fixed_scale" /opt/golden/test_regression.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && chmod 555 /opt/golden \
 && chmod 444 /opt/golden/test_regression.py \
 && test ! -d /tmp/upstream-fix-clone \
 && echo "golden test extracted, throwaway clone removed"

# 4) Fix-direction confirmation IN THIS IMAGE: apply the one-line upstream
#    fix, plant the golden test, run the whole test file, then restore the
#    tree. This proves both the golden test passes with the fix and that the
#    project's own suite stays green (370 passed = 369 existing + golden).
RUN cat > /tmp/fixdir.sh <<'EOF'
#!/bin/bash
set -u
export PATH=/usr/local/bin:$PATH
cd /app/src
python - <<'PY'
p = "statsmodels/regression/linear_model.py"
s = open(p).read()
old = ('            res.cov_kwds["description"] = descriptions["fixed_scale"]\n'
       '\n'
       '            res.cov_kwds["scale"] = scale = kwargs.get("scale", 1.0)\n'
       '            res.cov_params_default = scale * res.normalized_cov_params')
new = ('            res.cov_kwds["description"] = descriptions["fixed_scale"]\n'
       '            res.cov_kwds["scale"] = scale = kwargs.get("scale", 1.0)\n'
       '            res.scale = scale\n'
       '            res.cov_params_default = scale * res.normalized_cov_params')
assert old in s, "fix anchor not found"
open(p, "w").write(s.replace(old, new))
print("fix applied for fix-direction confirmation")
PY
cp /opt/golden/test_regression.py statsmodels/regression/tests/test_regression.py
python -m pytest statsmodels/regression/tests/test_regression.py -q -p no:cacheprovider \
    > /tmp/fixdir.log 2>&1 || { echo "FIX-DIRECTION SUITE FAILED"; tail -20 /tmp/fixdir.log; exit 1; }
grep -q "370 passed, 2 skipped" /tmp/fixdir.log \
    || { echo "unexpected suite result:"; tail -5 /tmp/fixdir.log; exit 1; }
python -m pytest statsmodels/regression/tests/test_regression.py \
    -k test_ols_wls_fixed_scale -q -p no:cacheprovider \
    > /tmp/golden.log 2>&1 || { echo "GOLDEN TEST FAILED"; tail -10 /tmp/golden.log; exit 1; }
grep -q "1 passed" /tmp/golden.log || { echo "golden unexpected:"; tail -5 /tmp/golden.log; exit 1; }
git checkout -q -- statsmodels/regression/linear_model.py \
                         statsmodels/regression/tests/test_regression.py
rm -f test-data.xml
test -z "$(git status --porcelain)" \
    || { echo "tree not restored after fix-direction check"; git status --porcelain | head -20; exit 1; }
echo "fix-direction OK: golden passes, 370 passed, tree restored clean"
EOF
RUN chmod 755 /tmp/fixdir.sh \
 && su -s /bin/bash worker -c '/tmp/fixdir.sh' \
 && rm -f /tmp/fixdir.sh

# 5) Belt: the fix commit must NOT be reachable from the trial clone, and
#    the clone must hold exactly one commit (the parent). The golden test at
#    /opt/golden came through the throwaway clone only.
RUN cd /app/src \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list --all | wc -l)" = 1 \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# 6) Record sha256 pins of the golden test, of the pristine pre-fix module,
#    and of the interpreters/toolchain, so the verifier can detect
#    substitution. /opt is read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_regression.py > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/linear_model_parent.py > /opt/pins/prefix-lm.sha256 \
 && sha256sum /usr/local/bin/python3.12 /usr/local/bin/pip /usr/local/bin/pytest \
              /usr/bin/gcc /usr/bin/git /usr/bin/bash \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins \
 && chmod 444 /opt/pins/*.sha256 \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 6 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-lm.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix module + toolchain pinned"

# 7) Final permissions for the trial (root or uid 1000).
RUN chmod -R a+rwX /app/src

# Build-time /tmp artifacts must not survive into the image: on this host's
# (rootless) overlay, a stale file baked into a layer with non-root ownership
# is not writable by a later container user and breaks every subsequent
# verifier log write. Delete them now (removal only needs /tmp's sticky
# world-writable directory permission, which is always available).
RUN rm -f /tmp/editable.log /tmp/fixdir.log /tmp/golden.log /tmp/check_parent.py /tmp/fixdir.sh \
 && echo "build-time /tmp artifacts removed"

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app

CMD ["/bin/bash"]