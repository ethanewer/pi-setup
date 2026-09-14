# bracket-flood: redis RESTORE silently drops keys when the relative TTL is
# so large that adding the current command time overflows a signed 64-bit
# timestamp (command replies OK, the key is treated as already expired and
# vanishes; REPLACE deletes the old value and expired_keys increments).
#
# The image contains a REAL upstream clone of redis/redis checked out at the
# PARENT commit of the upstream fix, i.e. the last commit that still contains
# the bug. The clone is initialised fresh and a single shallow --no-tags
# fetch of the pinned parent SHA is made, so the fix commit is not reachable
# from /app/src by any ref, object or reflog entry. The project's own
# regression test for the bug (tests/unit/dump.tcl as of the fix commit) is
# extracted through a THROWAWAY bare clone that is deleted afterwards, into
# /opt/golden, and never enters the task tree.
#
# redis is built once here (default jemalloc build, exactly like the mining
# run) so a trial only ever does incremental rebuilds; the agent's job is
# localise + fix + rebuild.

FROM bench-base:ubuntu-24.04

# The pinned buggy revision (parent of the upstream fix) and the fix
# revision (used ONLY to extract the regression test file as raw bytes).
ARG PARENT_SHA=3d15ede58ad862996f9b23d3500cad2a5c7fb0f4
ARG FIX_SHA=48cc562064dbb52ef3f9cc1a5aa32db6811f5871

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Build toolchain (gcc/make) plus Tcl, because the project's own test
# framework runs on tclsh. procps/netcat are small conveniences for the test
# harness and the reproducer's readiness probe.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential tcl tcl-dev procps netcat-openbsd \
 && rm -rf /var/lib/apt/lists/*

# Pin the clone to the buggy parent commit and nothing else: fresh repo,
# single shallow --no-tags fetch of the pinned SHA, detached checkout.
# No remote-tracking ref is created, so the clone holds exactly one commit
# and the upstream fix commit is not present at all.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/redis/redis.git \
 && git fetch --depth 1 --no-tags origin ${PARENT_SHA} \
 && git checkout -qf FETCH_HEAD \
 && test "$(git rev-parse --verify HEAD^{commit} 2>/dev/null)" = "${PARENT_SHA}" \
 && ! grep -q "add_overflow_ll" src/cluster.c \
 && echo "bug present: restoreCommand adds the relative TTL without an overflow guard"

# Belt: the fix commit must never be reachable from the working clone.
RUN cd /app/src \
 && if git cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi

# The project's own regression test for this bug, from the FIX commit, kept
# as raw bytes outside the clone so the fix never enters the tree.
RUN git init -q /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/redis/redis.git \
 && git fetch --depth 1 --no-tags origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/unit/dump.tcl > /opt/golden/dump.tcl \
 && test -s /opt/golden/dump.tcl \
 && grep -q "RESTORE with a TTL that overflows when added to the current time" /opt/golden/dump.tcl \
 && cd / \
 && rm -rf /tmp/fixsrc

# Build the whole tree once at image-build time (default jemalloc build),
# so trial-time work is only an incremental rebuild of changed sources.
# The recursive permission fix is folded into the SAME RUN as the build: a
# layer is written once, so the chmod is committed with the build instead of
# rewriting the entire compiled tree into a second copy-on-write layer.
RUN cd /app/src \
 && make -j$(nproc) > /tmp/redis-build.log 2>&1 \
 && test -x src/redis-server \
 && test -x src/redis-cli \
 && tail -3 /tmp/redis-build.log \
 && rm -f /tmp/redis-build.log \
 && chmod -R a+rwX /app

WORKDIR /app

# files/ lands in /app AFTER the build, so it gets its own small chmod here;
# the two files are plain files, so this is a non-recursive chmod and the
# final modes are identical to the old `chmod -R a+rwX /app` end state.
COPY files/ /app/
RUN chmod a+rwX /app/reproduce.sh /app/reproduce.tcl \
 && chmod +x /app/reproduce.sh /app/reproduce.tcl

CMD ["/bin/bash"]