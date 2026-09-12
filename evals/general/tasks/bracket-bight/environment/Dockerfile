# bracket-bight: debugging task on the real expressjs/express codebase.
#
# The agent is handed the real express repository checked out at the parent
# commit 59e205a5 (the pre-fix state of upstream issue #4893). At that commit
# res.send() writes a Content-Length header even when the response already
# carries a Transfer-Encoding header; HTTP/1.1 forbids both together and
# Node's own HTTP client rejects such a response outright
# ("Content-Length can't be present with Transfer-Encoding"), so streaming
# responses never reach the client. The agent must reproduce the failure,
# localise the cause inside the real tree and fix it.
#
# Leak-vector guards for this family (the tree is byte-audited and trials have
# no network, but upstream master already contains the fix, and the trial
# image is what the agent can read):
#   * /app/src is created with `git init` + a single by-hash fetch, so the
#     ONLY object that ever enters its store is the pinned parent commit.
#     Upstream master (where the fix is already merged) is never cloned, so no
#     ref or object in the agent's repo exposes the fixed code. A build-time
#     assertion confirms the fix object is absent from /app/src.
#   * The project's own regression test for the bug is extracted from the FIX
#     commit into /opt/golden using a scratch clone under /tmp that is deleted
#     immediately afterwards; the fix commit is never fetched into /app/src.
#
# Network exists while the image builds and NOT during the trial, so every
# fetch (the two shallow clones/checks) and the dependency install happen
# here, and node_modules stays in the image.

FROM bench-base:node-22

SHELL ["/bin/bash", "-lc"]

# Git safety for uid-1000 trials, plus a build identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Immutable pins, resolved from https://github.com/expressjs/express
# UPSTREAM_SHA: the pre-fix parent commit the agent receives.
# FIX_SHA:      the upstream fix commit, used only to extract the golden test.
ARG UPSTREAM_SHA=59e205a57a04fced6bb7b8ec0b5dec29461a9996
ARG FIX_SHA=18e5985b8a9d5e8423db0a9121f22bdaecd5b120

RUN test -n "$UPSTREAM_SHA" && test -n "$FIX_SHA" \
 && test "$(echo "$UPSTREAM_SHA" | wc -c)" = 41 \
 && test "$(echo "$FIX_SHA" | wc -c)" = 41

# --- copies the two small authored files the agent starts with ---------------
COPY files/ /app/

# --- the agent's workspace: real express tree at the pinned parent commit ---
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --quiet --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git rev-list --count HEAD)" = "1" \
 && git cat-file -e "$FIX_SHA^{commit}" 2>/dev/null && { echo "FIX OBJECT PRESENT IN /app/src - LEAK"; exit 1; } || true

# --- dependencies warmed for the trial (no network at trial time) -----------
RUN . ~/.nvm/nvm.sh >/dev/null 2>&1; cd /app/src \
 && npm install --no-audit --no-fund --loglevel=error \
 && test -d node_modules/supertest && test -d node_modules/mocha \
 && test -x node_modules/.bin/mocha

# --- golden test: the project's own regression file, taken from the fix ----
# commit, never committed to this repository. Scratch clone, deleted after.
RUN git init -q /tmp/golden-src \
 && cd /tmp/golden-src \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA":test/res.send.js > /opt/golden/res.send.js \
 && cd / \
 && rm -rf /tmp/golden-src \
 && grep -q "when Transfer-Encoding header is present" /opt/golden/res.send.js \
 && diff -q <(git -C /app/src show HEAD:test/res.send.js) /opt/golden/res.send.js >/dev/null \
   && { echo "golden file identical to parent - expected 4 added tests"; exit 1; } || true

# --- trusted-bytes manifest. The verifier executes code from the writable,
# gitignored node_modules tree (/app/src/node_modules/.bin/mocha) and loads
# the HTTP client from it (/app/src/node_modules/supertest), and it runs
# /app/reproduce.js. A hostile agent is therefore able to pass every check by
# replacing the gitignored mocha binary and stubbing supertest while leaving
# the tracked source bug in place (demonstrated: reward 1 with lib/response.js
# untouched). This manifest pins the build-time bytes of exactly those
# surfaces; the verifier recomputes it under penalty of reward 0, so the only
# remaining way to a 1 is an honest fix in the tracked tree.
RUN cd /app/src \
 && { sha256sum /app/reproduce.js; \
      find node_modules \( -type f -o -type l \) -print0 | sort -z \
        | while IFS= read -r -d '' f; do \
            if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"; \
            else sha256sum "$f"; fi; \
          done; \
    } > /opt/golden/trusted.sha256 \
 && test -s /opt/golden/trusted.sha256 \
 && grep -q " /app/reproduce.js" /opt/golden/trusted.sha256 \
 && grep -q "L node_modules/.bin/mocha" /opt/golden/trusted.sha256 \
 && grep -q "node_modules/supertest/" /opt/golden/trusted.sha256

# --- recorded failure at the parent commit (informational; must exit 0) -----
RUN cd /app/src && (node /app/reproduce.js 2>&1 || true) | head -5

# Thread-pool pins (this task is pure JavaScript; kept for sweep consistency).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

WORKDIR /app