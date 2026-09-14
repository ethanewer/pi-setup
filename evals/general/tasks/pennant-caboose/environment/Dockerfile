# pennant-caboose: redis XSETID ENTRIESADDED leaves consumer-group
# entries_read above a lowered entries_added (negative lag, unloadable RDB).
#
# The image contains a REAL upstream clone of redis/redis checked out at the
# PARENT commit of the upstream fix (upstream issue redis/redis#15489),
# i.e. the last commit that still contains the bug. The clone is initialised
# fresh and a single shallow --no-tags fetch of the pinned parent SHA is
# made, so the fix commit is not reachable from /app/src by any ref, object
# or reflog entry. The project's own regression test for the bug
# (tests/unit/type/stream-cgroups.tcl as of the fix commit) is extracted
# through a THROWAWAY bare clone that is deleted afterwards, into
# /opt/golden, and never enters the task tree. The fix commit's source
# changes are NOT extracted at all: the oracle re-derives the fix from the
# symptom, as the agent is required to.
#
# The verifier derives its own pristine pre-fix server at verify time by
# checking the parent's src/t_stream.c back out of the single-commit clone,
# rebuilding incrementally and then restoring the agent's file, so the
# agent's reproduction is run against the genuine pre-fix tree concept
# without any snapshot that the agent could tamper with.
#
# redis is built once here (default developer/jemalloc build, exactly like
# the mining run) so a trial only ever does incremental rebuilds; the
# agent's job is localise + fix + rebuild.

FROM bench-base:ubuntu-24.04

# The pinned buggy revision (parent of the upstream fix) and the fix
# revision (used ONLY to extract the regression test file as raw bytes).
ARG PARENT_SHA=8f365337d48c8a264bc9f3381c7b8cc12ffb51d2
ARG FIX_SHA=4f20cb48934463db5970bd476461b2d57af3f38d

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Build toolchain (gcc/make) plus Tcl, because the project's own test
# framework runs on tclsh.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential tcl tcl-dev \
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
 && grep -q 'void xsetidCommand' src/t_stream.c \
 && ! grep -q 'prev_entries_added' src/t_stream.c \
 && echo "bug present: xsetidCommand lowers entries_added without clamping group entries_read"

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
 && git show ${FIX_SHA}:tests/unit/type/stream-cgroups.tcl > /opt/golden/stream-cgroups.tcl \
 && test -s /opt/golden/stream-cgroups.tcl \
 && grep -q "XSETID ENTRIESADDED clamps group entries_read and keeps the RDB loadable" /opt/golden/stream-cgroups.tcl \
 && cd / \
 && rm -rf /tmp/fixsrc

# Build the whole tree once at image-build time (default jemalloc build),
# so the trial only does incremental rebuilds. The chmod that makes the
# tree writable by the trial user (uid 1000) lives in THIS SAME RUN: a
# later standalone chmod layer would write a second copy of the whole
# redis tree into the image (the v4.2 duplicate-bytes anti-pattern).
RUN cd /app/src \
 && make -j$(nproc) > /tmp/redis-build.log 2>&1 \
 && test -x src/redis-server \
 && test -x src/redis-cli \
 && tail -3 /tmp/redis-build.log \
 && rm -f /tmp/redis-build.log \
 && chmod -R a+rwX /app

WORKDIR /app

COPY files/ /app/

CMD ["/bin/bash"]