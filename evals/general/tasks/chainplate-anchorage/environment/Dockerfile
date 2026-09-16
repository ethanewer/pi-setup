# ---------------------------------------------------------------------------
# chainplate-anchorage: matplotlib Transform.contains_branch_seperately
# reports per-axis containment wrongly for composite transforms containing a
# blended (per-axis) transform, and returns a list where a pair of booleans
# is documented (upstream issue #28383).
#
# The image clones matplotlib/matplotlib and checks out upstream PARENT commit
# 74c7f9a598c4e32b3f551f75ed965f446d786ab1 (immediately before upstream commit
# 00cbd9cd3255dcbcb75e3090b144a8e18a900247 fixed issue #28383), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src (asserted below). The golden regression
# test file is extracted from the fix commit in a throwaway clone that is
# deleted, so the fix bytes never land in the working clone either.
#
# The project is installed in editable mode (`pip install --no-build-isolation
# -e .`), so the agent's edits to .py files under /app/src/lib are live
# without any reinstall. The C extensions (incl. vendored freetype/harfbuzz/
# qhull) are compiled at image build time; at trial time pytest triggers only
# the fast incremental meson editable loader.
#
# Size hygiene: the clone, the editable build and the chmod -R a+rwX live in
# ONE RUN, so /app/src occupies a single layer. A chmod in a RUN of its own,
# after the RUN that compiled the tree, would write a second copy of every
# byte into a new layer (copy-on-write). Creating the tree writable in the
# same layer that produced it stores each byte once. The end state is
# unchanged: /app/src and /app are a+rwX for whichever uid the trial uses.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=74c7f9a598c4e32b3f551f75ed965f446d786ab1
ARG UPSTREAM_SHA_FIX=00cbd9cd3255dcbcb75e3090b144a8e18a900247

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

# ---- working clone + editable build + writable tree, all in ONE RUN -------
# buggy parent commit only, fix commit unreachable; the tree is compiled and
# then chmodded a+rwX in this same layer (see header comment).
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && ! git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
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
 && test -f /app/src/lib/matplotlib/tests/test_transforms.py \
 && chmod -R a+rwX /app/src && chmod a+rwX /app

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree).
# The fix-commit test_transforms.py contains the regression assertions added
# for this issue inside TestBasicTransform.test_contains_branch:
#   blend = mtransforms.BlendedGenericTransform(self.tn2, self.stack2)
#   x, y = blend.contains_branch_seperately(self.stack2_subset)
#   stack_blend = self.tn3 + blend
#   sx, sy = stack_blend.contains_branch_seperately(self.stack2_subset)
#   assert x is sx is False
#   assert y is sy is True
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${UPSTREAM_SHA_FIX}:lib/matplotlib/tests/test_transforms.py \
      > /opt/golden/test_transforms.py \
 && test -s /opt/golden/test_transforms.py \
 && grep -q "def test_contains_branch" /opt/golden/test_transforms.py \
 && grep -q "stack_blend.contains_branch_seperately" /opt/golden/test_transforms.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_transforms.py

# ---- build-time confirmation that the image ships the mined failing state ----
# The bug must be present in the baked image (read-only check, no writes): the
# composite of a non-affine transform and a blended transform must report
# (False, False) for a y-component it actually contains, exactly as mined.
RUN cd /app/src && python3 - <<'EOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.transforms as mtransforms
from matplotlib.transforms import Transform, Affine2D

class NonAffineForTest(Transform):
    is_affine = False
    output_dims = 2
    input_dims = 2
    def __init__(self, real_trans, *a, **k):
        self.real_trans = real_trans
        super().__init__(*a, **k)
    def transform_non_affine(self, values):
        return self.real_trans.transform(values)
    def transform_path_non_affine(self, path):
        return self.real_trans.transform_path(path)

ta1 = Affine2D().rotate(3.14159 / 2)
ta2 = Affine2D().translate(10, 0)
ta3 = Affine2D().scale(1, 2)
tn1 = NonAffineForTest(Affine2D().translate(1, 2))
tn2 = NonAffineForTest(Affine2D().translate(1, 2))
tn3 = NonAffineForTest(Affine2D().translate(1, 2))
stack2 = ta1 + tn1 + ta2 + ta3
ss = tn1 + ta2 + ta3
blend = mtransforms.BlendedGenericTransform(tn2, stack2)
x, y = blend.contains_branch_seperately(ss)
sx, sy = (tn3 + blend).contains_branch_seperately(ss)
print('smoke: blend=(%r, %r) composite+blend=(%r, %r)' % (x, y, sx, sy))
# the blended transform must already answer per-axis correctly ...
assert x is False and y is True, 'blended transform answers changed; re-mine'
# ... while the composite must still answer wrongly: the bug is present.
assert sx is False and sy is False, 'bug NOT present at parent commit!'
print('smoke ok: the parent-commit bug is present in this image')
EOF

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]