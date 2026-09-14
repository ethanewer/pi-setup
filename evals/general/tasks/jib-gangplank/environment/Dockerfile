# ---------------------------------------------------------------------------
# jib-gangplank: matplotlib pie chart with all-zero wedge sizes crashes deep
# in path drawing with 'cannot convert float NaN to integer' instead of a
# clear error (upstream issue #30007).
#
# The image clones matplotlib/matplotlib and checks out upstream PARENT
# commit 2d87c9584499f7619b3c84b89121a27c80d2373e (immediately before upstream
# commit 91740933b658437016063f904030706d84b4502b fixed issue #30007), so the
# agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test file (the
# fix-commit lib/matplotlib/tests/test_axes.py, which appends
# test_pie_all_zeros) is extracted from the fix commit in a throwaway clone
# that is deleted afterwards, so the fix bytes never land in the working
# clone either; only /opt/golden/ holds them.
#
# The project is installed in editable mode (`pip install --no-build-isolation
# -e .`), so the agent's edits to .py files under /app/src/lib are live
# without any reinstall. The C extensions (incl. vendored freetype/harfbuzz/
# qhull) are compiled at image build time; at trial time pytest triggers only
# the fast incremental meson editable loader.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=2d87c9584499f7619b3c84b89121a27c80d2373e
ARG UPSTREAM_SHA_FIX=91740933b658437016063f904030706d84b4502b

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    MPLBACKEND=Agg \
    MPLCONFIGDIR=/tmp/mplconfig

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config ninja-build \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && ! git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/. The sha file is consumed by the verifier to pin the golden
# content byte-for-byte at verification time.
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${UPSTREAM_SHA_FIX}:lib/matplotlib/tests/test_axes.py \
      > /opt/golden/test_axes.py \
 && test -s /opt/golden/test_axes.py \
 && grep -q "def test_pie_all_zeros" /opt/golden/test_axes.py \
 && grep -q "All wedge sizes are zero" /opt/golden/test_axes.py \
 && sha256sum /opt/golden/test_axes.py | cut -d' ' -f1 > /opt/golden/test_axes.py.sha \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_axes.py /opt/golden/test_axes.py.sha

# ---- runtime and build environment, fully pinned (no network at trial) ------
# pyparsing MUST stay < 3.2.0: matplotlib's pytest configuration turns
# warnings into errors and pyparsing 3.2.0's resetCache deprecation otherwise
# aborts test collection with a PyparsingDeprecationWarning error.
RUN pip install --no-cache-dir \
      meson-python==0.16.0 \
      pybind11==3.1.0 \
      setuptools-scm==10.2.3 \
      ninja==1.13.2 \
      meson==1.12.0 \
      setuptools==84.0.0 \
      numpy==2.5.3 \
      contourpy==1.3.3 \
      cycler==0.12.1 \
      kiwisolver==1.5.1 \
      fonttools==4.65.0 \
      packaging==26.3 \
      certifi==2026.7.22 \
      pillow==12.3.0 \
      pyparsing==3.1.4 \
      python-dateutil==2.9.0.post0 \
      pytest==8.4.2 \
 && cd /app/src \
 && pip install --no-build-isolation -e . > /tmp/mpl-build.log 2>&1 \
 || { tail -60 /tmp/mpl-build.log; exit 1; } \
 && python3 -c "import matplotlib; print('installed matplotlib', matplotlib.__file__)" \
 && test -f /app/src/lib/matplotlib/tests/test_axes.py \
 && mkdir -p /tmp/mplconfig \
 && python3 -c "import matplotlib, matplotlib.pyplot as plt; f = plt.figure(); f.text(0.5, 0.5, 'warm'); f.savefig('/tmp/fc-warm.png')" \
 && chmod -R a+rwX /tmp/mplconfig \
 && chmod -R a+rwX /app/src && chmod a+rwX /app

# ---- build-time confirmation that the image ships the mined failing state ----
# 1) The bug is present: pie with all-zero wedge sizes raises the cryptic NaN
#    ValueError, and the parent tree contains no 'All wedge sizes are zero'.
# 2) The golden regression test FAILS against the parent tree.
RUN cd /app/src && python3 - <<'EOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
try:
    ax.pie([0, 0], labels=['A', 'B'])
except ValueError as e:
    msg = str(e)
    print('smoke: pie([0, 0]) raised ValueError: %r' % msg)
    assert 'All wedge sizes are zero' not in msg, 'guard already present?'
    assert 'NaN' in msg, 'unexpected failure mode: %r' % msg
else:
    raise SystemExit('smoke FAIL: pie([0, 0]) did not raise at the parent commit')
print('smoke ok: the parent-commit crash is present in this image')
EOF

RUN cd /app/src && cp /opt/golden/test_axes.py lib/matplotlib/tests/test_axes.py \
 && ( python3 -m pytest "lib/matplotlib/tests/test_axes.py::test_pie_all_zeros" \
        -q -p no:cacheprovider > /tmp/golden-smoke.out 2>&1 || true ) \
 && ! grep -qE "1 passed" /tmp/golden-smoke.out \
 && echo "smoke ok: golden test test_pie_all_zeros FAILS on the parent tree" \
 && rm lib/matplotlib/tests/test_axes.py \
 && git -C /app/src checkout -q -- lib/matplotlib/tests/test_axes.py \
 && chmod a+rwX /app/src/lib/matplotlib/tests/test_axes.py /app/src/result_images 2>/dev/null; \
    chmod -R a+rwX /app/src/result_images 2>/dev/null || true

WORKDIR /app

CMD ["/bin/bash"]