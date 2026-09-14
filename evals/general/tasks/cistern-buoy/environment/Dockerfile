# cistern-buoy: fix a real curl bug -- one extreme Strict-Transport-Security
# max-age header wipes the on-disk HSTS cache.
#
# The image contains a REAL upstream clone of curl/curl checked out at the
# PARENT commit of the upstream fix, i.e. the last commit that still contains
# the bug. The fix commit is NEVER fetched into the clone: the repository is
# initialised fresh and a single shallow fetch of the pinned parent SHA is
# made, so the fix commit is not reachable from /app/src by any ref, object
# or reflog entry. The project's own regression test for the bug
# (tests/data/test1862, added by the fix commit) is downloaded as a raw file
# into /opt/golden and is projected onto the tree by the verifier only.
#
# curl is built once here (debug build, upstream developer settings) so the
# trial only ever does incremental rebuilds; the agent's job is localise +
# fix + rebuild.

FROM bench-base:ubuntu-24.04

# The pinned buggy revision (parent of the upstream fix) and the fix
# revision (used ONLY to extract the regression test file as raw bytes).
ARG PARENT_SHA=b8172ada19b1211aeed64f473b4a53e941c6fabe
ARG FIX_SHA=08d50a791b3197a3d0a4fc2f778e243f5501c67e

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Build toolchain for curl from source + the C debugger for localisation.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential autoconf automake libtool pkg-config \
      openssl libssl-dev zlib1g-dev libpsl-dev libzstd-dev libbrotli-dev \
      gdb strace ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Pin the clone to the buggy parent commit and nothing else: fresh repo,
# single shallow fetch of the pinned SHA, detached checkout. --no-tags and a
# raw-SHA fetch mean no remote-tracking ref is created, so the clone holds
# exactly one commit and the upstream fix commit is not present at all.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/curl/curl.git \
 && git fetch --depth 1 --no-tags origin ${PARENT_SHA} \
 && git checkout -qf FETCH_HEAD \
 && test "$(git rev-parse --verify HEAD^{commit} 2>/dev/null)" = "${PARENT_SHA}"

# The project's own regression test for this bug, from the FIX commit, kept
# as raw bytes outside the clone so the fix never enters the tree.
RUN mkdir -p /opt/golden \
 && curl -fsSL "https://raw.githubusercontent.com/curl/curl/${FIX_SHA}/tests/data/test1862" -o /opt/golden/test1862 \
 && grep -q "HSTS with extreme max-age" /opt/golden/test1862

# Per-task notes for the trial, copied in before the build so the chmod below
# can cover them in the same layer.
WORKDIR /app

COPY files/ /app/

# Build everything once at image-build time: libcurl+curl (debug), then the
# test harness (test servers, libtest tools, unit bundles). The tree is left
# a+rwX in THIS SAME layer: docker layers are copy-on-write, so a chmod -R in
# a later RUN of its own would rewrite every file of the compiled tree into a
# new layer and double the image size. The trial may run as uid 1000; the
# agent must still be able to edit + rebuild, and to write /app/diagnosis.md.
RUN cd /app/src \
 && autoreconf -fi \
 && ./configure --with-openssl --enable-debug \
 && make -j$(nproc) \
 && make -C tests all \
 && chmod -R a+rwX /app

CMD ["/bin/bash"]