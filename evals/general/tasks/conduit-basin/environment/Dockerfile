# conduit-basin: redis --bigkeys/--keystats omits a zero-size key from the
# biggest-key summary.
#
# The image contains a REAL upstream clone of redis/redis checked out at the
# PARENT commit of the upstream fix, i.e. the last commit that still contains
# the bug. The clone is initialised fresh and a single shallow --no-tags
# fetch of the pinned parent SHA is made, so the fix commit is not reachable
# from /app/src by any ref, object or reflog entry. The project's own
# regression test for the bug (tests/integration/redis-cli.tcl as of the fix
# commit) is extracted through a THROWAWAY bare clone that is deleted
# afterwards, into /opt/golden, and never enters the task tree.
#
# redis is built once here (default jemalloc build, exactly like the mining
# run) so a trial only ever does incremental rebuilds; the agent's job is
# localise + fix + rebuild.

FROM bench-base:ubuntu-24.04

# The pinned buggy revision (parent of the upstream fix) and the fix
# revision (used ONLY to extract the regression test file as raw bytes).
ARG PARENT_SHA=21ce96878529bf8b31298ec417407c578c1e6278
ARG FIX_SHA=669b2a1316f5b35ecf964281b77c054ff28dc934

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
 && grep -Fq 'if(type->biggest<sizes[i])' src/redis-cli.c \
 && grep -Fq 'if (current_type->biggest > 0)' src/redis-cli.c \
 && grep -Fq 'if (type->biggest<size)' src/redis-cli.c \
 && echo "bug present: biggest-key bookkeeping uses strict '<' from a zero base"

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
 && git show ${FIX_SHA}:tests/integration/redis-cli.tcl > /opt/golden/redis-cli.tcl \
 && test -s /opt/golden/redis-cli.tcl \
 && grep -q "bigkeys reports a zero-size key as the biggest key of its type" /opt/golden/redis-cli.tcl \
 && cd / \
 && rm -rf /tmp/fixsrc

# Build the whole tree once at image-build time (default jemalloc build),
# so trial-time work is only an incremental rebuild of changed sources.
# The chmod runs in this SAME layer as the build: a separate `chmod -R`
# RUN would write a second copy of every compiled file into a new layer
# (docker layers are copy-on-write), doubling the tree's storage cost.
RUN cd /app/src \
 && make -j$(nproc) > /tmp/redis-build.log 2>&1 \
 && test -x src/redis-server \
 && test -x src/redis-cli \
 && tail -3 /tmp/redis-build.log \
 && rm -f /tmp/redis-build.log \
 && chmod -R a+rwX /app

WORKDIR /app

COPY files/ /app/
# Only reproduce.sh is new since the build RUN chmod'd the tree; chmod that
# one file (a full -R here would re-store the whole compiled tree).
RUN chmod a+rwX /app /app/reproduce.sh \
 && chmod +x /app/reproduce.sh

CMD ["/bin/bash"]