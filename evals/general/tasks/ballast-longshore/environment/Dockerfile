# ---------------------------------------------------------------------------
# ballast-longshore: matplotlib ScalarFormatter.set_useOffset treats the
# numeric value 1 as the boolean True (upstream issue #29532).
#
# The image clones matplotlib/matplotlib and checks out upstream PARENT commit
# 91d115ec161286b70da1447f53844b909247741f (immediately before upstream commit
# 05a66bb2a46a67d0bb716239ecafa681b2832ea3 fixed issue #29532), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test file is
# extracted from the fix commit in a throwaway clone that is deleted, so the
# fix bytes never land in the working clone either.
#
# The project is installed in editable mode (`pip install --no-build-isolation
# -e .`), so the agent's edits to .py files under /app/src/lib are live
# without any reinstall. The C extensions (incl. vendored freetype/harfbuzz/
# qhull) are compiled at image build time; at trial time pytest triggers only
# the fast incremental meson editable loader.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=91d115ec161286b70da1447f53844b909247741f
ARG UPSTREAM_SHA_FIX=05a66bb2a46a67d0bb716239ecafa681b2832ea3

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    MPLBACKEND=Agg

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
# /opt/golden/ (never in this repository's tree).
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${UPSTREAM_SHA_FIX}:lib/matplotlib/tests/test_ticker.py \
      > /opt/golden/test_ticker.py \
 && test -s /opt/golden/test_ticker.py \
 && grep -q "def test_set_use_offset_int" /opt/golden/test_ticker.py \
 && grep -q "def test_set_use_offset_bool" /opt/golden/test_ticker.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_ticker.py

# ---- runtime and build environment, fully pinned (the trial has no network) -
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
 && test -f /app/src/lib/matplotlib/tests/test_ticker.py \
 && chmod -R a+rwX /app/src \
 && chmod a+rwX /app

# ---- build-time confirmation that the image ships the mined failing state ----
# The bug must be present in the baked image (read-only check, no writes):
# set_useOffset(1) must produce offset=0 / useOffset=True exactly as mined.
RUN cd /app/src && python3 - <<'EOF'
import matplotlib
matplotlib.use('Agg')
from matplotlib.ticker import ScalarFormatter
f = ScalarFormatter()
f.set_useOffset(1)
print('smoke: set_useOffset(1) -> offset=%r useOffset=%r' % (f.offset, f.get_useOffset()))
assert f.offset == 0 and f.get_useOffset(), 'bug not present at parent commit!'
print('smoke ok: the parent-commit bug is present in this image')
EOF

# The tree (clone + compiled C extensions + any meson editable-loader
# metadata) is made writable for whichever uid the trial uses by the
# `chmod -R a+rwX /app/src` at the END of the build RUN above, i.e. in the
# SAME layer that produced it. Removing it here avoids a copy-on-write
# duplicate of the whole /app/src tree: a standalone `chmod -R` RUN after the
# build would re-store every file's bytes in a new layer (in gunwale-tideway
# this produced two layers of exactly 2.74 GB).

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]