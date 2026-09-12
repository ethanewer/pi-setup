# cistern-coral: fix a real draw_flood out-of-bounds regression in the real
# libvips tree.
#
# The image carries a shallow clone of libvips pinned to the PARENT of the
# upstream fix (the commit right before the draw_flood start-point bounds
# check), and that tree is ALREADY built with meson/ninja and installed, with
# pyvips and pytest bound to it, so the agent's work is one source edit plus
# an incremental `ninja -C build install`. The project's own regression test
# (the fix-era test_draw.py) is extracted into /opt/golden at build time and
# is never committed in this tree (the tree is byte-audited).
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=ea7e608844b85f4d296821e59b2483369b301b53
ARG GOLDEN_SHA=7cfd70a869de8fe3f3a22b32f755e382130b716c

# Build toolchain plus every optional libvips dependency, exactly the recipe
# the bug was verified against. apt is deliberately not version-pinned
# (Debian rotates its archives); binutils is needed for the strings
# assertions below.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    git build-essential meson ninja-build pkg-config binutils \
    libglib2.0-dev libexpat1-dev libjpeg-dev libpng-dev libtiff-dev \
    liblcms2-dev libfftw3-dev liborc-0.4-dev libwebp-dev libfontconfig1-dev \
    libpango1.0-dev libopenjp2-7-dev librsvg2-dev libgsf-1-dev libexif-dev \
    libzstd-dev liblzma-dev libbz2-dev libxml2-dev python3-dev python3-pip \
 && rm -rf /var/lib/apt/lists/*

# git identity + safe.directory: the trial may run as uid 1000 against a
# root-owned clone, and agents may want to git commit their fix.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# The upstream tree at the PARENT of the fix. Shallow-fetched by exact SHA so
# the clone holds only that commit on the `baseline` branch: no refs, no
# master, and the fix commit is NOT reachable from this clone (the golden
# test is extracted from a separate throwaway clone below, then deleted).
# ---------------------------------------------------------------------------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/libvips/libvips.git \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout -b baseline FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# ---------------------------------------------------------------------------
# The golden regression test: the fix-era test/test-suite/test_draw.py
# (the parent draw suite + test_draw_flood_out_of_bounds). Extracted via a
# throwaway clone so the fix commit's bytes never touch /app/src; sha256 is
# verified against the upstream blob (fail closed). The clone is deleted.
# ---------------------------------------------------------------------------
RUN git init /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git remote add origin https://github.com/libvips/libvips.git \
 && git fetch --depth 1 origin "$GOLDEN_SHA" \
 && mkdir -p /opt/golden \
 && git show "$GOLDEN_SHA":test/test-suite/test_draw.py \
      > /opt/golden/test_draw.py \
 && test "$(sha256sum /opt/golden/test_draw.py | cut -d' ' -f1)" = \
      e4b03bed7b31f5d9083833aac3123e6bd2350b7b43a21e14401b304dcccf7e10 \
 && rm -rf /tmp/golden-clone

# ---------------------------------------------------------------------------
# Build + install the library AS SHIPPED: the parent, with the bug live.
# The agent edits one source file and only needs `ninja -C build install`
# on top of this layer. Fail-closed assertions:
#   - the installed .so must NOT yet contain the fix's error message, which
#     also guards the stale-soname shadowing this commit era is prone to
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && meson setup build \
 && ninja -C build \
 && ninja -C build install \
 && ldconfig \
 && test "$(strings /usr/local/lib/x86_64-linux-gnu/libvips.so.42* | grep -c 'start point out of image')" = "0" \
 && echo "build: parent library built, installed, and still buggy (no bounds-check string)"

# pyvips (binds to the installed libvips at import time) + pytest for the
# project's own test suite. Exact pins resolved against this base image.
RUN python3 -m pip install --break-system-packages --no-cache-dir \
      pyvips==3.2.0 pytest==8.4.2

# Snapshot the installed Python binding tree (pyvips + its abi extension +
# pytest/cffi) immediately after the pins and BEFORE the broad chmod below,
# so the verifier can reject a "fix" that monkeypatches the binding instead
# of repairing the C library. Bytecode caches are excluded on both sides
# (trial imports legitimately create them); everything else is content
# hashed, including the file list. /opt stays root-only after the chmod.
RUN python3 - <<'PY'
import hashlib
import os

ROOT = "/usr/local/lib/python3.12/dist-packages"
manifest = []
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d != "__pycache__"]
    for f in sorted(fn):
        if f.endswith((".pyc", ".pyo")) or f.endswith("~"):
            continue
        p = os.path.join(dp, f)
        try:
            h = hashlib.sha256(open(p, "rb").read()).hexdigest()
        except OSError:
            continue
        manifest.append("%s  %s" % (h, p))
open("/opt/python-site.sha256", "w", encoding="utf-8").write(
    "\n".join(sorted(manifest)) + "\n")
PY
RUN chmod 644 /opt/python-site.sha256 \
 && test -s /opt/python-site.sha256 \
 && echo "binding snapshot: $(wc -l < /opt/python-site.sha256) files hashed"

# The trial runs on one CPU; pin any numeric thread pools to 1.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    VIPS_CONCURRENCY=1

# uid-1000 tolerance: the agent must edit the clone AND be able to run
# `ninja install` into /usr/local, whichever uid (root or 1000) harbor uses.
RUN chmod -R a+rwX /app/src /usr/local

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

# ---------------------------------------------------------------------------
# Liveness gate, fail closed: the bug must be live in THIS image.
#   - /app/reproduce.py must report the bug (itself exit non-zero),
#   - the fix-era golden regression must FAIL against the parent build.
# ---------------------------------------------------------------------------
RUN if python3 /app/reproduce.py > /tmp/parent-repro.log 2>&1; then \
      echo "UNEXPECTED: reproducer exited 0 at the parent commit" >&2; \
      cat /tmp/parent-repro.log >&2; \
      exit 1; \
    fi \
 && if python3 -m pytest -q -p no:cacheprovider \
        /opt/golden/test_draw.py::TestDraw::test_draw_flood_out_of_bounds \
        > /tmp/parent-golden.log 2>&1; then \
      echo "UNEXPECTED: golden regression PASSED against the parent build" >&2; \
      cat /tmp/parent-golden.log >&2; \
      exit 1; \
    fi \
 && echo "liveness: bug is live at the parent commit (reproducer non-zero, golden fails)"