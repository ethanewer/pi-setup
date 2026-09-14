# ---------------------------------------------------------------------------
# jackstay-larboard: librosa/librosa display.specshow boolean-data colourbar bug
# (upstream issue #2072).
#
# The image clones librosa/librosa and checks out upstream PARENT commit
# c7aa2ce80a100cd901945589437c5acc55e38739 — the revision immediately before
# upstream commit 6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771 fixed the bug — so
# the agent gets the real repository with the real bug still in it: specshow of
# a boolean 2D array infers the boolean grayscale colormap but leaves the
# image's normalizer at the default continuous Normalize(0,1), so an attached
# colourbar spans the whole colour ramp with many intermediate shades even
# though the data has two values. The image itself looks correct — only the
# colourbar is misleading.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. The fix commit is never fetched
# into /app/src; the golden regression test and its baseline image are
# extracted through a separate throwaway clone that is deleted afterwards.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=c7aa2ce80a100cd901945589437c5acc55e38739
ARG FIX_SHA=6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/librosa/librosa.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && du -sh /app/src

# ---- runtime and test environment, fully pinned (the trial has no network) -
# librosa requires numpy>=2.1, scipy>=1.15, numba>=0.61, scikit-learn>=1.6,
# joblib, decorator, soundfile, pooch, soxr, lazy_loader, msgpack; the
# [tests] extra adds matplotlib. matplotlib is pinned to 3.11.1 because (a) the
# project's pytest-mpl baseline PNGs were verified to render identically under
# this version and (b) the discriminating BoundaryNorm semantics were verified
# against it. numpy 2.5.3 matches the mining run.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MPLBACKEND=Agg \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install numpy==2.5.3 scipy==1.18.1 numba==0.67.0 scikit-learn==1.9.1 \
            joblib==1.6.0 decorator==5.3.1 soundfile==0.14.0 \
            pooch==1.9.0 soxr==1.1.0 lazy_loader==0.5 msgpack==1.2.2 \
            matplotlib==3.11.1 pytest==9.1.1 pytest-mpl==0.19.0 \
            pytest-cov==7.1.0 \
 && cd /app/src \
 && pip install -e '.[tests]'

# ---- pristine PRE-FIX package at /opt/prefix ---------------------------------
# The verifier runs the agent's own reproduction against this copy and requires
# it to FAIL, proving the symptom is real and that the reproduction targets it.
# Extracted from the pinned commit's own git objects, so it is byte-exact and
# cannot contain the fix. Read-only at trial time.
RUN mkdir -p /opt/prefix \
 && git -C /app/src archive ${UPSTREAM_SHA} librosa | tar -x -C /opt/prefix \
 && test -f /opt/prefix/librosa/display.py \
 && grep -c "is_boolean_cmap" /opt/prefix/librosa/display.py | grep -q "^0$" \
 && chmod -R a+rX /opt/prefix

# ---- fail-closed: the bug must reproduce in THIS image with THESE pins -------
# Both directions are confirmed inside this build, against the exact pinned
# environment: (1) the installed package (/app/src, parent) and the pristine
# pre-fix package (/opt/prefix) must both attach a plain Normalize to a boolean
# specshow image (the bug); (2) the REAL upstream fixed display.py, taken from
# a throwaway clone of the fix commit that is deleted immediately afterwards,
# must attach a BoundaryNorm([0, 0.5, 1]) (the fixed behaviour). The throwaway
# clone also supplies the golden regression test, its pytest-mpl baseline image
# and the test-suite conftest, sha256-pinned into /opt/pins.
RUN python - <<'EOF'
import os, sys, shutil

os.environ["MPLBACKEND"] = "Agg"
import matplotlib

matplotlib.use("Agg")
import numpy as np, matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm

rng = np.random.default_rng(0)
data = rng.random((8, 8)) > 0.5


def norm_type_for_pkg(pkgdir):
    old = list(sys.path)
    sys.path.insert(0, pkgdir)
    for m in list(sys.modules):
        if m == "librosa" or m.startswith("librosa."):
            del sys.modules[m]
    try:
        import librosa.display
    finally:
        sys.path[:] = old
    fig, ax = plt.subplots()
    img = librosa.display.specshow(data, ax=ax)
    plt.close(fig)
    return type(img.norm).__name__, img.norm


# 1) installed package must show the bug
name, cls = norm_type_for_pkg("/app/src")
print("installed (/app/src) boolean-specshow norm:", name)
assert name == "Normalize", "expected the bug (plain Normalize) at the parent"
assert not isinstance(cls, BoundaryNorm)

# 2) pristine pre-fix copy must show the bug too
name, cls = norm_type_for_pkg("/opt/prefix")
print("/opt/prefix boolean-specshow norm:", name)
assert name == "Normalize", "expected the bug (plain Normalize) at /opt/prefix"

# 3) throwaway clone of the FIX commit (deleted below after the golden files
#    are extracted): use the REAL upstream fixed display.py for the fixed
#    direction, and pull the golden regression test + baseline image from it.
rc = os.system(
    "git clone --depth 1 --no-checkout https://github.com/librosa/librosa.git /tmp/fixsrc "
    "&& cd /tmp/fixsrc && git fetch --depth 1 origin 6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771"
)
assert rc == 0, "throwaway fix clone failed"
os.makedirs("/tmp/fixchk", exist_ok=True)
shutil.copytree("/app/src/librosa", "/tmp/fixchk/librosa")
rc = os.system(
    "cd /tmp/fixsrc && git show 6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771:librosa/display.py"
    " > /tmp/fixchk/librosa/display.py"
)
assert rc == 0, "could not extract fixed display.py"
name, cls = norm_type_for_pkg("/tmp/fixchk")
print("/tmp/fixchk (upstream-fixed) boolean-specshow norm:", name)
assert isinstance(cls, BoundaryNorm), "fix direction did not produce BoundaryNorm"
assert [float(b) for b in cls.boundaries] == [0.0, 0.5, 1.0]

# 4) extract the golden regression test, its baseline image and the conftest.
os.makedirs("/opt/golden", exist_ok=True)
for srcp, dstp in [
    ("tests/test_display.py", "/opt/golden/test_display.py"),
    ("tests/conftest.py", "/opt/golden/conftest.py"),
    ("tests/baseline_images/test_display/test_specshow_boolean_norm.png",
     "/opt/golden/test_specshow_boolean_norm.png"),
]:
    rc = os.system(
        "cd /tmp/fixsrc && git show 6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771:%s > %s"
        % (srcp, dstp)
    )
    assert rc == 0 and os.path.getsize(dstp) > 0, "golden extraction failed for %s" % srcp
assert "def test_specshow_boolean_norm" in open("/opt/golden/test_display.py", encoding="utf-8").read()
assert open("/opt/golden/test_specshow_boolean_norm.png", "rb").read(4) == b"\x89PNG"

# 5) pins, then destroy every trace of the fix commit.
os.makedirs("/opt/pins", exist_ok=True)
rc = os.system(
    "sha256sum /opt/golden/test_display.py /opt/golden/conftest.py "
    "/opt/golden/test_specshow_boolean_norm.png /opt/prefix/librosa/display.py "
    "> /opt/pins/golden.sha256"
)
assert rc == 0
shutil.rmtree("/tmp/fixsrc", ignore_errors=True)
shutil.rmtree("/tmp/fixchk", ignore_errors=True)
print("BOTH DIRECTIONS CONFIRMED IN IMAGE (parent=Normalize, upstream-fixed=BoundaryNorm); golden extracted")
EOF
RUN chmod -R a+rX /opt/golden /opt/pins \
 && chmod 555 /opt/golden /opt/pins \
 && chmod 444 /opt/golden/* /opt/pins/golden.sha256 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && echo "golden test + baseline + pre-fix package extracted and pinned"

# ---- belt: prove the fix commit is not reachable from the trial clone ---------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git rev-list --all --count)" = "1" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# ---- let the trial run as root or uid 1000 ------------------------------------
RUN chmod -R a+rwX /app \
 && chown -R 1000:1000 /app 2>/dev/null || true

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]