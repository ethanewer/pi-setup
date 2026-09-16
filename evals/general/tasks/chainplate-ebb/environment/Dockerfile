# ---------------------------------------------------------------------------
# chainplate-ebb: scipy.optimize.minimize silently rewrites the caller's
# Bounds object in place (real upstream issue scipy/scipy#25880).
#
# The image clones scipy/scipy and checks out upstream PARENT commit
# 68942fb357ee133e75709e91959d322325fffb90 (immediately before upstream
# commit b92b297a5a0c372600bffffd4dc83513be9bfd39 fixed issue #25880), so the
# agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY superproject commit object in
# the /app/src object store is the parent itself. Neither the fix commit nor
# any later history is reachable from /app/src (asserted below). The golden
# regression test file is extracted from the fix commit in a throwaway clone
# that is deleted, so the fix bytes never land in this task tree (the tree is
# byte-audited) and the working clone never contains the fix commit.
#
# The project is installed in editable mode from /app/src
# (`pip install --no-build-isolation -e .`): the compiled extension modules
# are built at image build time, and any edit the agent makes to a plain .py
# file under /app/src/scipy (e.g. scipy/optimize) is live for the next
# `import scipy` without any rebuild or reinstall. The trial has no network,
# so this layer IS the warm cache.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=68942fb357ee133e75709e91959d322325fffb90
ARG UPSTREAM_SHA_FIX=b92b297a5a0c372600bffffd4dc83513be9bfd39

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential gfortran pkg-config ninja-build git ca-certificates \
      libopenblas-dev \
 && rm -rf /var/lib/apt/lists/* \
 && pkg-config --exists openblas && echo "openblas: $(pkg-config --modversion openblas) $(pkg-config --libs openblas)"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
# `git init` + one depth-1 fetch of the pinned SHA means the object store in
# /app/src holds ONLY the parent commit. The upstream repository's meson
# subprojects (array_api_compat, array_api_extra, cobyqa, HiGHs, unuran, xsf,
# boost_math, scipy-mathjax) are git submodules pinned by the parent commit's
# tree; they are fetched next (network exists at build time only).
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/scipy/scipy.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && ! git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && cd /app/src \
 && git submodule update --init --depth 1 --recursive 2>&1 | tail -8 \
 && test -f subprojects/array_api_compat/README.md \
 && test -f subprojects/array_api_extra/README.md \
 && test -f subprojects/cobyqa/README.rst \
 && test -f subprojects/highs/README.md \
 && test -f subprojects/unuran/README.md \
 && test -f subprojects/xsf/README.md \
 && test -f subprojects/boost_math/math/README.md \
 && echo "submodules at parent-pinned SHAs"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree). The fix-commit
# test_optimize.py is byte-identical to the parent's except for the two new
# regression tests for this issue:
#   test_minimize_does_not_mutate_bounds (parametrized over 8 methods)
#   test_minimize_bounds_reusable_across_sizes
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/scipy/scipy.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${UPSTREAM_SHA_FIX}:scipy/optimize/tests/test_optimize.py \
      > /opt/golden/test_optimize.py \
 && test -s /opt/golden/test_optimize.py \
 && grep -q "def test_minimize_does_not_mutate_bounds" /opt/golden/test_optimize.py \
 && grep -q "def test_minimize_bounds_reusable_across_sizes" /opt/golden/test_optimize.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_optimize.py

# Belt: prove the fix commit is not reachable from the trial clone and the
# clone is still exactly the single parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list --all --count)" = "1"

# ---- build dependencies, fully pinned (the trial has no network) ------------
# scipy 2.0.0.dev0 (parent commit) requires meson-python >= 0.15, Cython >=
# 3.2, pybind11 >= 2.13.2, pythran >= 0.18.1, numpy >= 2.0; the system
# libopenblas-dev provides the BLAS/LAPACK implementation for the meson
# `blas=openblas, lapack=openblas` options.
RUN pip install --no-cache-dir \
      numpy==2.5.3 \
      meson-python==0.21.1 \
      meson==1.12.0 \
      ninja==1.13.2 \
      Cython==3.3.0 \
      pybind11==3.1.0 \
      pythran==0.19.0 \
      setuptools==84.0.0 \
      pytest==9.1.1 \
 && python3 -c "import numpy; print('numpy', numpy.__version__)" \
 && python3 -c "import mesonpy; print('meson-python', mesonpy.__version__)" \
 && python3 -c "import Cython; print('Cython', Cython.__version__)"

# ---- full source build + editable install of scipy from /app/src ------------
# The expensive compile happens here, once, as a cached image layer. The
# editable install keeps the source tree live: pure-Python edits the agent
# makes at trial time are picked up on the next import.
# `compile-args=-j 16` caps ninja's parallelism so the compile stays bounded
# in RAM no matter how many CPUs the build host offers (scipy is a big
# C/C++/Fortran build; 16 parallel jobs is a good memory/speed trade-off).
RUN cd /app/src \
 && pip install --no-build-isolation -e . \
      --config-settings='compile-args=-j 16' > /tmp/scipy-build.log 2>&1 \
 || { tail -100 /tmp/scipy-build.log; exit 1; } \
 && python3 - <<'EOF'
import scipy
print('INSTALLED scipy', scipy.__version__, scipy.__file__)
assert scipy.__file__.startswith('/app/src'), scipy.__file__
from scipy import optimize
print('scipy.optimize import OK')
EOF

# ---- build-time confirmation that the image ships the mined failing state ----
# The bug must be present in the baked image (read-only check for the caller's
# object; nothing here "uses up" the mutation): passing a dimension-agnostic
# Bounds made from scalar limits into minimize() rewrites the caller's object
# in place - the scalar limits are replaced by arrays broadcast to the current
# problem's size, so `bounds.lb is lb` / `bounds.ub is ub` are False.
RUN cd /app/src && python3 - <<'EOF'
import numpy as np
from scipy import optimize
bounds = optimize.Bounds(0., np.inf)
lb, ub = bounds.lb, bounds.ub
print('before: lb=%r shape=%s ub=%r shape=%s' % (lb, lb.shape, ub, ub.shape))
optimize.minimize(optimize.rosen, [0.5, 0.5], method='trust-constr', bounds=bounds)
print('after:  lb is lb:%s ub is ub:%s lb.shape=%s ub.shape=%s %s'
      % (bounds.lb is lb, bounds.ub is ub, bounds.lb.shape, bounds.ub.shape,
         bounds.lb))
assert not (bounds.lb is lb and bounds.ub is ub), \
    'BUG NOT PRESENT: the caller Bounds was not mutated; re-mine'
print('smoke ok: the parent-commit mutation bug is present in this image')
EOF

# The tree must stay writable for whichever uid the trial uses (meson editable
# loader and __pycache__ writes happen under /app/src at trial time); the agent
# must also be able to write /app/explanation.md.
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true \
 && chmod a+rwX /app

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]