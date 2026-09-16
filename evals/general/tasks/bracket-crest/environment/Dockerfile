# bracket-crest: debugging task on the real prettier/prettier codebase.
#
# The agent is handed the real prettier repository checked out at the parent
# commit 45a4a75e (the pre-fix state of upstream issue #19878). At that commit
# a Markdown setext heading whose text spans several source lines, written
# inside a blockquote, is corrupted on format: the blockquote markers are
# printed inline between the words (`> Multi > Line`) instead of one marker
# per source line, so the reformatted file no longer means the same thing.
# The agent must reproduce the failure, localise the cause inside the real
# tree and fix it.
#
# Leak-vector guards for this family (the tree is byte-audited and trials have
# no network, but upstream master already contains the fix, and the trial
# image is what the agent can read):
#   * /app/src is created with `git init` + a single by-hash fetch, so the
#     ONLY object that ever enters its store is the pinned parent commit.
#     Upstream master (where the fix is already merged) is never cloned, so no
#     ref or object in the agent's repo exposes the fixed code. A build-time
#     assertion confirms the fix object is absent from /app/src.
#   * The project's own regression test fixture for the bug
#     (tests/format/markdown/heading/setext/, which contains blockquote.md
#     that only exists at the FIX commit) is extracted from the FIX commit
#     into /opt/golden using a scratch clone under /tmp that is deleted
#     immediately afterwards; the fix commit is never fetched into /app/src.
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
ARG UPSTREAM_SHA=45a4a75ea639e69d35f885224818e6698561fc11
ARG FIX_SHA=07184252aa4a84fcc542f34e5e70291a08b5de3a

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
 && test -x node_modules/.bin/jest \
 && git checkout -- yarn.lock \
 && test -z "$(git status --porcelain)"

# --- recorded failure at the parent commit (the mined repro): the CLI ---
# corrupts the input; assert the corruption is present, fail-closed.
RUN cd /app/src \
 && printf '> Multi\n> Line\n> ===\n' > /tmp/a.md \
 && out="$(node bin/prettier.js /tmp/a.md)" \
 && printf '%s\n' "$out" | grep -q '> Multi > Line' \
 && echo "parent reproduced: $(printf '%s\n' "$out" | head -n 1)"

# --- golden test: the project's own regression setext suite from the fix ---
# commit (format.test.js + blockquote.md fixture + snapshots), never
# committed to this repository. Scratch clone, deleted after.
RUN git init -q /tmp/golden-src \
 && cd /tmp/golden-src \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden/setext \
 && git archive "$FIX_SHA" tests/format/markdown/heading/setext \
      | tar -x -C /opt/golden/setext --strip-components=5 \
 && cd / \
 && rm -rf /tmp/golden-src \
 && test "$(find /opt/golden/setext -type f | wc -l)" -eq 10 \
 && test -f /opt/golden/setext/format.test.js \
 && test -f /opt/golden/setext/blockquote.md \
 && test -f /opt/golden/setext/__snapshots__/format.test.js.snap \
 && grep -q 'blockquote.md format 1' /opt/golden/setext/__snapshots__/format.test.js.snap \
 && ! grep -q '> Multi > Line' /opt/golden/setext/__snapshots__/format.test.js.snap \
 && diff -q <(git -C /app/src show HEAD:tests/format/markdown/heading/setext/format.test.js) /opt/golden/setext/format.test.js \
 && echo "golden setext suite extracted from fix commit"

# --- verifier integrity anchors -------------------------------------------
# 1. Trusted-binary mirror: the verifier runs with PATH=/opt/pi-tools:/usr/bin:/bin
#    (never /usr/local/bin, which is agent-writable in the trial container).
#    node itself lives at /usr/local/bin/node, so a private copy is made here.
#    An agent can still shadow /usr/bin or /opt/pi-tools as root; this defeats
#    the documented "plant a wrapper in /usr/local/bin" attack class.
# 2. jest manifest: sha256 aggregate of node_modules/.bin/jest and the jest
#    package tree, recorded at build time for the verifier to re-check so a
#    replaced/fake jest cannot make both jest-based stages vacuous.
# 3. /opt/golden is made root-owned and write-protected in the image layer
#    (the verifier independently byte-checks it against SHA-256 constants
#    carried in tests/test.sh on the fresh /tests mount).
RUN mkdir -p /opt/pi-tools \
 && for b in node git diff timeout sha256sum cmp cp sed sort find tail grep cat mkdir rm tr wc cut date env bash; do \
      p="/usr/bin/$b"; [ -e "$p" ] || p="/bin/$b"; [ -e "$p" ] || p="/usr/local/bin/$b"; \
      [ -e "$p" ] && cp -a "$p" /opt/pi-tools/ 2>/dev/null || true; \
    done \
 && test -x /opt/pi-tools/node && test -x /opt/pi-tools/git && test -x /opt/pi-tools/diff \
 && chmod -R a+rX /opt/pi-tools \
 && cd /app/src \
 && { find node_modules/jest node_modules/jest-* node_modules/@jest -type f 2>/dev/null | LC_ALL=C sort | xargs -r sha256sum; \
     sha256sum node_modules/.bin/jest 2>/dev/null; } \
      | sha256sum | cut -d' ' -f1 > /opt/golden/jest.sha256 \
 && test -s /opt/golden/jest.sha256 \
 && chown -R root:root /opt/golden && chmod -R a-w /opt/golden \
 && echo "verifier anchors: $(ls /opt/pi-tools | wc -l) trusted tools, jest manifest $(cat /opt/golden/jest.sha256)"

# Thread-pool pins (this task is pure JavaScript; kept for sweep consistency).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

WORKDIR /app