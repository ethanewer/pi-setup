# bracket-channel: fix a real clamping regression in the real libvips tree.
#
# The image carries a shallow clone of libvips pinned to the PARENT of the
# upstream fix (the commit right before the unpremultiply clamping fix), and
# that tree is ALREADY built with meson/ninja and installed, with pyvips and
# pytest bound to it, so the agent's work is one source edit plus an
# incremental `ninja install`. The project's own regression test (the
# fix-era test_conversion.py) is extracted into /opt/golden at build time
# and is never committed in this tree (the tree is byte-audited).
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=92b95531d198abf9ca40aaa3f67dd6d7f4cfa2bd
ARG GOLDEN_SHA=dbf559add2807037d89a16b7a9e371e8267c0f63

# Build toolchain plus every optional libvips dependency the conversion and
# foreign ops need (this is the recipe the issue was verified with; apt is
# deliberately not version-pinned, Debian rotates its archives).
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    git build-essential meson ninja-build pkg-config \
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
# The golden regression test: the fix-era test/test-suite/test_conversion.py.
# Extracted via a throwaway clone so the fix commit's bytes never touch
# /app/src; sha256 is verified against the upstream blob (fail closed).
# ---------------------------------------------------------------------------
RUN git init /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git remote add origin https://github.com/libvips/libvips.git \
 && git fetch --depth 1 origin "$GOLDEN_SHA" \
 && mkdir -p /opt/golden \
 && git show "$GOLDEN_SHA":test/test-suite/test_conversion.py \
      > /opt/golden/test_conversion.py \
 && test "$(sha256sum /opt/golden/test_conversion.py | cut -d' ' -f1)" = \
      1d9f925b990c6cda3f9327544038c923dcfd149923ac5199cc8e2f02113f05e4 \
 && rm -rf /tmp/golden-clone

# ---------------------------------------------------------------------------
# Build + install the library AS SHIPPED: the parent, with the bug live.
# The agent edits one source file and only needs `ninja -C /app/src/build
# install` on top of this layer.
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && meson setup build \
 && ninja -C build \
 && ninja -C build install \
 && ldconfig

# Snapshot the byte-identity of the installed library as shipped. The
# verifier requires the agent's rebuilt+reinstalled libvips core to DIFFER
# from this snapshot: an agent that leaves the underlying .so untouched (a
# Python-site wrapper, or a fix that is never rebuilt/installed) must score
# 0 even if every readback through pyvips looks correct.
RUN find /usr/local/lib -type f -name 'libvips.so.*' \
      -exec sha256sum {} \; \
  > /opt/libvips-shipped.sha256 \
 && test -s /opt/libvips-shipped.sha256

# pyvips (binds to the installed libvips at import time) + pytest for the
# project's own test suite. Exact pins resolved against this base image.
RUN python3 -m pip install --break-system-packages --no-cache-dir \
      pyvips==3.2.0 pytest==8.4.2

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