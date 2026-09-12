# bracket-beacon — upstream-regression task on cure53/DOMPurify (issue #1320).
#
# The image contains the real DOMPurify checkout at the PARENT commit of the
# fix for the "function-form ADD_ATTR skips URI validation" bug. The fix
# commit's own regression test (test/test-suite.js) is extracted at build time
# into /opt/golden/ from an EPHEMERAL repository that is deleted immediately
# afterwards, so the fix commit object never lands inside /app/src/.git and is
# not reachable from the checkout the agent works in (nor is any branch: only
# the parent SHA is ever fetched into /app/src, shallow and history-severed).
#
# The agent must reproduce the bug, localise it and fix it in the real source.
# The verifier rebuilds dist/ from the agent's source with the project's own
# `npm run build`, then runs the golden regression suite through the project's
# own jsdom runner, then the authored hidden cases. The trial has no network;
# everything needed is warmed here.
FROM bench-base:node-22

# git-uid-1000 safety and a build identity (agents may want to use git).
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- Immutable pins -------------------------------------------------------
# UPSTREAM_PARENT_SHA: the buggy revision the agent is given.
# UPSTREAM_FIX_SHA:    the upstream fix; used ONLY to extract its regression
#                      test, never fetched into /app/src.
ARG UPSTREAM_PARENT_SHA=591c429c8db48797bdbd90a44f90d7ea5a88fbf7
ARG UPSTREAM_FIX_SHA=6bc35973f0c6e7fa2344037af024fe0cf9cfa6e2

# --- Golden regression test (fix-era test/test-suite.js), then gone --------
RUN git init -q /tmp/golden-extract \
 && cd /tmp/golden-extract \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch --depth 1 -q origin "$UPSTREAM_FIX_SHA" \
 && test "$(git rev-parse "$UPSTREAM_FIX_SHA")" = "$UPSTREAM_FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$UPSTREAM_FIX_SHA":test/test-suite.js > /opt/golden/test-suite.js \
 && test -s /opt/golden/test-suite.js \
 && cd / \
 && rm -rf /tmp/golden-extract

# --- The buggy checkout: fetch ONLY the parent commit ---------------------
# Shallow (--depth 1) and pinned by 40-hex SHA; the shallow file severs the
# history so the fix commit cannot be walked to even if it were known.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch --depth 1 -q origin "$UPSTREAM_PARENT_SHA" \
 && git checkout --detach -q "$UPSTREAM_PARENT_SHA" \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_PARENT_SHA" \
 && test "$(git rev-list --count HEAD)" = "1"

# --- Warm every dependency at build time (the trial has no network) -------
WORKDIR /app/src
RUN npm install --no-audit --no-fund

# Prove the build toolchain already works here. Building the buggy source
# yields exactly the committed dist (verified byte-identical at authoring
# time), so the working tree stays clean.
RUN npm run build >/dev/null

# Fail closed: the bug must be present in this image. The reproduction must
# exit 1 (dangerous URI survived) and print the surviving javascript: value.
COPY files/repro.js /tmp/beacon-repro.js
RUN NODE_PATH=/app/src/node_modules node /tmp/beacon-repro.js > /tmp/beacon-repro-before.txt 2>&1 || true
RUN grep -q 'javascript:' /tmp/beacon-repro-before.txt \
 && grep -q 'RESULT: FAIL' /tmp/beacon-repro-before.txt \
 && rm -f /tmp/beacon-repro.js /tmp/beacon-repro-before.txt

WORKDIR /app
# Single-CPU sweep: keep any native numeric pools pinned to one thread.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
COPY files/ /app/