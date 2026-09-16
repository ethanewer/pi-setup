# ---------------------------------------------------------------------------
# capstan-cleat: matplotlib Axes.axline draws a line given a very small
# (non-zero) slope as perfectly horizontal (upstream issue #28386).
#
# The image clones matplotlib/matplotlib and checks out upstream PARENT commit
# 7722dead68f8de43480f1f58386d03396bd5d58e (immediately before upstream commit
# e90952ffac668bd5115c4009bf20dd6e595c3cd5 fixed issue #28386), so the agent
# gets the real repository with the real bug still in it. AxLine.get_transform
# decides the line is horizontal with `np.isclose(slope, 0)`; with numpy's
# default atol of 1e-8 every slope with |slope| <= 1e-8 is snapped to a
# perfectly horizontal line, so axline((0, 0), slope=1e-14) renders with zero
# tilt (dy == 0.0 in the transform). The upstream fix compares `slope == 0`
# exactly, so only a true zero slope is horizontal and tiny slopes keep their
# tilt (dy ~ 3.7e-12 for slope 1e-14).
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in /app/src is
# the parent itself; the fix commit is unreachable (asserted both here and in
# the verifier). The upstream regression test (the fix-commit
# lib/matplotlib/tests/test_lines.py, which adds test_axline_small_slope) is
# extracted at build time through a SEPARATE throwaway clone under /tmp that
# is rm -rf'd afterwards, so the fix bytes never land in the working clone
# either, and copied to /opt/golden as harness-owned bytes.
#
# The project is installed in editable mode (`pip install --no-build-isolation
# -e .`), so the agent's edits to .py files under /app/src/lib are live
# without any rebuild. The C extensions (incl. vendored freetype/harfbuzz/
# qhull as meson subprojects, fetched at build time) are compiled once at
# image build time; at trial time pytest triggers only the fast incremental
# meson editable loader.
#
# Build-time fail-closed check: the parent-direction symptom (dy == 0.0) is
# re-observed inside this image with these exact pinned dependency versions.
# The fix direction is re-confirmed inside the final image by the oracle run
# (harbor run -a oracle) and by the author's own both-directions container run
# before registration; note that the editable install's import hook resolves
# `import matplotlib` to /app/src regardless of PYTHONPATH, so an in-tree
# throwaway copy cannot be used to run the fixed direction at build time.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=7722dead68f8de43480f1f58386d03396bd5d58e
ARG UPSTREAM_SHA_FIX=e90952ffac668bd5115c4009bf20dd6e595c3cd5
ARG GOLDEN_SHA256=86a8a8c942cb715ca9138a32099a0ccdf30c5d06d846028f60c9a829b42745a7

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
# /opt/golden/ (never in this repository's tree).
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${UPSTREAM_SHA_FIX}:lib/matplotlib/tests/test_lines.py \
      > /opt/golden/test_lines.py \
 && test "$(sha256sum /opt/golden/test_lines.py | cut -d' ' -f1)" = "${GOLDEN_SHA256}" \
 && grep -q "def test_axline_small_slope" /opt/golden/test_lines.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_lines.py

# ---- runtime and build environment, fully pinned (the trial has no network) -
# pyparsing MUST stay < 3.2.0: matplotlib's pytest configuration turns
# warnings into errors and pyparsing 3.2.0's resetCache deprecation otherwise
# aborts test collection. Pins match the verified mining environment and the
# sibling matplotlib tasks (chainplate-anchorage, ballast-longshore).
# The chmod of /app/src lives in the SAME RUN that populated it (COW hygiene:
# a separate chown/chmod layer would duplicate the whole tree).
RUN mkdir -p /app /tmp/mplconfig \
 && pip install --no-cache-dir \
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
 && test -f /app/src/lib/matplotlib/tests/test_lines.py \
 && rm -f /tmp/mpl-build.log \
 && chmod -R a+rwX /app/src /app /tmp/mplconfig

# ---- build-time confirmation that the image ships the mined failing state ----
# The bug must be present in the baked image (read-only check on the shipped
# tree): the transform of a 1e-14-slope axline must give dy == 0.0, exactly as
# mined. Fails the build if the bug is absent.
RUN cd /app/src && python3 - <<'EOF'
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
line = ax.axline((0, 0), slope=1e-14)
p1 = line.get_transform().transform_point((0, 0))
p2 = line.get_transform().transform_point((1, 1))
dy = p2[1] - p1[1]
print('smoke: parent dy =', dy)
assert dy == 0.0, 'bug NOT present at parent commit!'
print('smoke ok: the parent-commit bug is present in this image')
EOF

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]