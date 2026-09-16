# cistern-ferry: debugging task on the real prettier/prettier codebase.
#
# The agent is handed the real prettier repository checked out at the parent
# commit 7c5872f7 (the pre-fix state of upstream issue #19709). At that commit
# HTML attribute-name normalization is gated on whether the element has an
# entry in Prettier's per-element attribute table, so an attribute name like
# CLASS on a well-known tag that lacks per-element data (e.g. <span>) is left
# uppercase while the same attribute on a tag WITH per-element data (<div>) is
# rewritten to class. The same attribute therefore gets inconsistent casing
# depending on the tag. The agent must reproduce the failure, localise the
# cause inside the real tree and fix it.
#
# Leak-vector guards for this family (the tree is byte-audited and trials have
# no network, but upstream master already contains the fix, and the trial
# image is what the agent can read):
#   * /app/src is created with `git init` + a single by-hash fetch, so the
#     ONLY object that ever enters its store is the pinned parent commit.
#     Upstream master (where the fix is already merged) is never cloned, so no
#     ref or object in the agent's repo exposes the fixed code. A build-time
#     assertion confirms the fix object is absent from /app/src.
#   * The project's own regression test for the bug
#     (tests/format/html/attributes/lowercase/, which exists only at the FIX
#     commit) is extracted from the FIX commit into /opt/golden using a
#     scratch clone under /tmp that is deleted immediately afterwards; the fix
#     commit is never fetched into /app/src.
#
# Network exists while the image builds and NOT during the trial, so every
# fetch (the two shallow by-hash fetches) and the dependency install happen
# here, and node_modules stays in the image.

FROM bench-base:node-22

SHELL ["/bin/bash", "-lc"]

# Git safety for uid-1000 trials, plus a build identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Immutable pins, resolved from https://github.com/prettier/prettier
# UPSTREAM_SHA: the pre-fix parent commit the agent receives.
# FIX_SHA:      the upstream fix commit, used only to extract the golden test.
ARG UPSTREAM_SHA=7c5872f7a27b3eb249d0347fcfac989eca2cb70b
ARG FIX_SHA=bfb1eacd89ba5b3b6fd5f2faf7908da8bbd558a2

RUN test -n "$UPSTREAM_SHA" && test -n "$FIX_SHA" \
 && test "$(printf %s "$UPSTREAM_SHA" | wc -c)" = 40 \
 && test "$(printf %s "$FIX_SHA" | wc -c)" = 40

# --- copies the small authored files the agent starts with ---------------
COPY files/ /app/

# --- the agent's workspace: real prettier tree at the pinned parent commit ---
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --quiet --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git rev-list --count HEAD)" = "1" \
 && git cat-file -e "$FIX_SHA^{commit}" 2>/dev/null && { echo "FIX OBJECT PRESENT IN /app/src - LEAK"; exit 1; } || true

# --- dependencies warmed for the trial (no network at trial time) ---------
# npm rewrites yarn.lock during install; restore it so the tracked tree is
# byte-identical to the parent commit before the agent starts.
RUN . ~/.nvm/nvm.sh >/dev/null 2>&1; cd /app/src \
 && npm install --no-audit --no-fund --loglevel=error \
 && test -d node_modules/jest \
 && test -d node_modules/jest-light-runner \
 && test -d node_modules/outdent \
 && test -x node_modules/.bin/jest \
 && git checkout -- yarn.lock \
 && test -z "$(git status --porcelain)"

# --- recorded failure at the parent commit (the mined repro): the CLI ---
# leaves the <span> attribute uppercase while lowercasing the <div> one;
# assert the bug is present, fail-closed.
RUN cd /app/src \
 && if node /app/reproduce.js > /tmp/repro.out 2>&1; then \
      echo "FAIL: bug did not reproduce at the parent commit"; exit 1; \
    fi \
 && grep -q 'BUG REPRODUCED' /tmp/repro.out \
 && grep -q '<span CLASS=' /tmp/repro.out \
 && grep -q '<div class=' /tmp/repro.out \
 && echo "parent reproduced: $(grep -m1 '<span CLASS' /tmp/repro.out)"

# --- golden test: the project's own regression lowercase suite from the ---
# fix commit (format.test.js + snapshot), never committed to this
# repository. Scratch clone, deleted after.
RUN git init -q /tmp/golden-src \
 && cd /tmp/golden-src \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden/lowercase \
 && git archive "$FIX_SHA" tests/format/html/attributes/lowercase \
      | tar -x -C /opt/golden/lowercase --strip-components=5 \
 && cd / \
 && rm -rf /tmp/golden-src \
 && test "$(find /opt/golden/lowercase -type f | wc -l)" -eq 2 \
 && test -f /opt/golden/lowercase/format.test.js \
 && test -f /opt/golden/lowercase/__snapshots__/format.test.js.snap \
 && grep -q 'snippet: #0 format 1' /opt/golden/lowercase/__snapshots__/format.test.js.snap \
 && grep -q 'span class="should print as lowercase"' /opt/golden/lowercase/__snapshots__/format.test.js.snap \
 && ! git -C /app/src cat-file -e HEAD:tests/format/html/attributes/lowercase/format.test.js 2>/dev/null \
 && echo "golden lowercase suite extracted from fix commit"

# Thread-pool pins (this task is pure JavaScript; kept for sweep consistency).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

WORKDIR /app