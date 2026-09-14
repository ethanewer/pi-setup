# jetsam-head: libvips/libvips — icc_import of a float (0..1) RGB image
# produces all-black output (upstream issue #5123, fixed by upstream commit
# 736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f).
#
# The image creates a shallow clone of libvips pinned and detached on the
# PARENT commit f0c38f9a7d4bea39e1e1718db2b441c91880a871 (the real upstream
# bug is present in the working tree), builds it with meson/ninja and installs
# it system-wide, so /usr and /app/src/build both ARE the buggy parent build.
# The project's own regression test for the bug (test_icc_float_input, added
# by the fix commit to test/test-suite/test_colour.py) is extracted from the
# FIX commit at build time into /opt/golden/ through a separate throwaway bare
# clone under /tmp that is deleted before the layer commits, so the fix object
# is never reachable from the shipped repository at /app/src. The agent's
# repairs take effect through the in-tree build via LD_LIBRARY_PATH and the
# verifier re-derives everything by rebuilding from the agent's tree; /usr
# stays the pristine parent build so the pre-fix direction of the agent's
# reproduction can be re-run. libvips is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
# Single-CPU trial semantics; libvips runs its own thread pool, pin it.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 VIPS_CONCURRENCY=1

ARG UPSTREAM_SHA=f0c38f9a7d4bea39e1e1718db2b441c91880a871
ARG FIX_SHA=736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain and project dependencies ------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends git meson ninja-build pkg-config \
            patch libglib2.0-dev libexpat1-dev libjpeg-dev libpng-dev \
            libtiff-dev liblcms2-dev libfftw3-dev liborc-0.4-dev libwebp-dev \
            libfontconfig1-dev libpango1.0-dev libopenjp2-7-dev librsvg2-dev \
            libgsf-1-dev libexif-dev libzstd-dev liblzma-dev libbz2-dev \
            libxml2-dev python3-dev python3-pip \
 && rm -rf /var/lib/apt/lists/*

# pyvips and pytest, pinned; resolved against this base's python 3.12.
RUN pip3 install --break-system-packages --no-cache-dir \
        pyvips==3.2.0 pytest==8.3.5

# ---- working clone: buggy parent commit, fix commit unreachable -------------
# git init + fetch of exactly the parent SHA, so no other branch or tip
# snapshot ever exists in the clone the agent receives.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/libvips/libvips.git \
 && git fetch --depth 1 origin f0c38f9a7d4bea39e1e1718db2b441c91880a871 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git rev-parse --is-shallow-repository)" = "true" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone under /tmp, deleted before the layer commits; the fix
# commit object is therefore absent from the image AND from /app/src.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/libvips/libvips.git \
 && git fetch --depth 1 origin 736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f \
 && mkdir -p /opt/golden \
 && git show 736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f:test/test-suite/test_colour.py \
      > /opt/golden/test_colour.py \
 && test "$(sha256sum /opt/golden/test_colour.py | cut -d' ' -f1)" \
      = "8f7494f7bb8a6eb4a50a70daedee26ecbdb6f53509f4128d28019bfa24cdcced" \
 && grep -q "test_icc_float_input" /opt/golden/test_colour.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- pre-build the project (cached layer; the agent's edits are then --------
# ---- incremental) and open the tree for the trial uid in the SAME RUN --------
# (a separate chown/chmod layer would copy the tree, doubling image size).
RUN cd /app/src \
 && meson setup build --prefix=/usr > /tmp/meson-setup.log 2>&1 \
 && ninja -C build -j"$(nproc)" > /tmp/ninja.log 2>&1 \
 && ninja -C build install >> /tmp/ninja.log 2>&1 \
 && ldconfig \
 && chmod -R a+rwX /app/src

WORKDIR /app

CMD ["/bin/bash"]