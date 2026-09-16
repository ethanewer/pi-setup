# ---------------------------------------------------------------------------
# chainplate-drift: scikit-image's EllipseModel.estimate accepts fewer than 5
# data points (real upstream issue scikit-image/scikit-image#7648, fixed by
# upstream commit 96834cf3d57c4a9bad82a471a5548be3ad53a4fa).
#
# The image clones scikit-image/scikit-image and checks out upstream PARENT
# commit fff7deabe28fb6039c26588f751e9cad88354f19 (immediately before the fix),
# so the agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in /app/src's
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from the working clone. The project's regression test
# for the bug is extracted from the FIX commit in a throwaway clone that is
# deleted afterwards; the upstream test bytes live only at /opt/golden/ and
# never appear in this repository's tree.
#
# The project is installed editable with meson-python (pinned deps, era build
# flags), so the agent's edits under /app/src/skimage are live without any
# reinstall step. The build finishes by re-confirming BOTH directions inside
# this image against these exact pinned dependencies: at the parent commit the
# 4-point reproduction still returns True with fabricated parameters and the
# golden regression test FAILS ('DID NOT WARN'); after applying the guard the
# reproduction returns False with the RuntimeWarning and the golden test, plus
# the project's own ellipse/circle tests, PASS.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=fff7deabe28fb6039c26588f751e9cad88354f19
ARG FIX_SHA=96834cf3d57c4a9bad82a471a5548be3ad53a4fa

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/scikit-image/scikit-image.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree).
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/scikit-image/scikit-image.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:skimage/measure/tests/test_fit.py \
      > /opt/golden/test_fit.py \
 && test -s /opt/golden/test_fit.py \
 && test "$(sha256sum /opt/golden/test_fit.py | cut -d' ' -f1)" \
      = "5a8c9222b5ff03a5d4d28a4a80b7b77795ba9a6b2b403f1e342f70c3bcae904a" \
 && grep -q "def test_ellipse_model_estimate_failers" /opt/golden/test_fit.py \
 && grep -q "Need at least 5 data points to estimate an ellipse" /opt/golden/test_fit.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_fit.py

# ---- system toolchain for the build (apt is not version-pinned by design) ---
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*

# ---- runtime + test environment, fully pinned (the trial has no network) ----
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# numpy/scipy exact from the verified reproduction; Cython 3.0.x (the 3.1.x
# line is incompatible with this era's build), meson-python 0.16 era build;
# the rest are the project's runtime deps plus the test tooling.
RUN pip install setuptools==75.9.1 numpy==2.1.3 scipy==1.14.1 Cython==3.0.12 \
                 meson-python==0.16.0 ninja==1.11.1.1 pythran==0.16.0 \
                 lazy_loader==0.4 packaging==24.1 networkx==3.4.2 \
                 pytest==8.3.3 pytest-cov==5.0.0 \
                 pytest-faulthandler==2.0.1 pytest-doctestplus==1.2.1 \
                 pytest-localserver==0.8.1 pooch==1.8.2 asv==0.6.1 \
                 numpydoc==1.7.0

# Build once here so it is a cached image layer; the agent's work is
# incremental (pure-Python edits) on top of it.
RUN cd /app/src \
 && pip install -e . --no-build-isolation \
      --config-settings=setup-args=-Dcpp_std=c++17

# ---- build-time confirmation, direction 1: the image ships the bug ----------
# On the pristine parent tree / against the editable install: the 4-point
# reproduction must still return True with fabricated parameters, and the
# upstream regression test extracted from the fix commit (run straight from
# /opt/golden, never copying upstream bytes into the tree) must FAIL against
# the parent code ('DID NOT WARN'), exactly as mined. Tree stays untouched.
RUN <<EOF
set -e
cd /app/src
python3 <<'PYEOF2'
import numpy as np
from skimage.measure import EllipseModel
m = EllipseModel()
ok = m.estimate(np.array([[0., 0.], [1., 2.], [3., 1.], [4., 5.]]))
print('4-point estimate ->', ok, ' params ->', None if m.params is None else np.asarray(m.params))
assert bool(ok) is True, 'bug not present at parent: estimate did not claim success on 4 points'
PYEOF2
rc=0
python3 -m pytest /opt/golden/test_fit.py::test_ellipse_model_estimate_failers -o addopts= -p no:cacheprovider -q > /tmp/golden-parent.log 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo 'golden test unexpectedly passed at parent' >&2; exit 1; }
grep -q 'DID NOT WARN' /tmp/golden-parent.log || { echo 'expected DID NOT WARN in golden output' >&2; tail -20 /tmp/golden-parent.log >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ]
rm -f /tmp/golden-parent.log
EOF

# ---- build-time confirmation, direction 2: the guard fixes it ---------------
# Apply the same minimal guard the oracle ships, then on the live editable
# install: the 4-point reproduction must return False (params unset), the
# golden regression test must PASS, the project's own estimator suite (the
# golden, fix-era test_fit.py, whose one outdated regression test upstream
# updated in the same commit) must stay green, and every authored hidden-case
# expectation (4-point fabricated-fit vector, collinear/small-input
# silent-failure vector, genuine 5-point fit still recovering the truth) must
# hold. Tree restored afterwards.
RUN <<EOF
set -e
cd /app/src
cp skimage/measure/fit.py /tmp/fit.py.bak
python3 <<'PYEOF2'
src = open('/app/src/skimage/measure/fit.py').read()
marker = """        # Original Implementation: Ben Hammel, Nick Sullivan-Molina
        # another REFERENCE: [2] http://mathworld.wolfram.com/Ellipse.html
        _check_data_dim(data, dim=2)

"""
addition = """        if len(data) < 5:
            warn(
                "Need at least 5 data points to estimate an ellipse.",
                category=RuntimeWarning,
                stacklevel=2,
            )
            return False

"""
assert src.count(marker) == 1, 'insertion point not found'
open('/app/src/skimage/measure/fit.py', 'w').write(src.replace(marker, marker + addition))
PYEOF2
python3 <<'PYEOF2'
import warnings
import numpy as np
from skimage.measure import EllipseModel

# 4 arbitrary points: refuse, warn, fabricate nothing
m = EllipseModel()
ok = m.estimate(np.array([[0., 0.], [1., 2.], [3., 1.], [4., 5.]]))
print('4-point estimate ->', ok, ' params ->', m.params)
assert ok is False and m.params is None

# 3 collinear (golden input), 2 points and 1 point: exactly one warning each
for name, pts in [
    ('3 collinear', np.array([[50., 80.], [51., 81.], [52., 80.]])),
    ('2 points', np.array([[1.5, 2.5], [-3.0, 4.0]])),
    ('1 point', np.array([[7.0, -2.0]])),
]:
    m = EllipseModel()
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter('always')
        ok = m.estimate(pts)
    msgs = [str(x.message) for x in w]
    print(name, '->', ok, msgs)
    assert ok is False and len(msgs) == 1
    assert 'Need at least 5 data points to estimate an ellipse.' in msgs[0]

# genuine 5-point ellipse still fits with the true parameters
xc, yc, a, b, theta = 10.0, 15.0, 8.0, 4.0, np.deg2rad(30.0)
ct, st = np.cos(theta), np.sin(theta)
t = np.linspace(0.0, 2.0 * np.pi, 6)
xs = xc + a * ct * np.cos(t) - b * st * np.sin(t)
ys = yc + a * st * np.cos(t) + b * ct * np.sin(t)
m = EllipseModel()
ok = m.estimate(np.column_stack([xs, ys]))
print('5-point estimate ->', ok, ' params ->', np.round(m.params, 6))
assert ok is True
assert np.allclose(m.params, [xc, yc, a, b, theta], atol=1e-4)
assert np.max(np.abs(m.residuals(np.column_stack([xs, ys])))) < 1e-6
print('hidden-case expectations hold')
PYEOF2
python3 -m pytest /opt/golden/test_fit.py::test_ellipse_model_estimate_failers -o addopts= -p no:cacheprovider -q
python3 -m pytest /opt/golden/test_fit.py -o addopts= -p no:cacheprovider -q
git checkout -q -- skimage/measure/fit.py
[ -z "$(git status --porcelain --untracked-files=no)" ]
cmp skimage/measure/fit.py /tmp/fit.py.bak
rm -f /tmp/fit.py.bak
EOF

# ---- the final image: pristine parent tree, writable by the trial user ------
RUN chmod -R a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]