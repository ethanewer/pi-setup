# fender-hull: cure53/DOMPurify, upstream issue #1560 — IN_PLACE sanitize of a
# live subtree aborts mid-scrub when the root element shadows the document
# property the cleaner reads to build its traversal ("ownerDocument" clobber).
#
# The image clones DOMPurify SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree) and installs its pinned dependencies via
# the committed lockfile (`npm ci`; jsdom 29.1.1). The upstream FIX commit is
# fetched only into a throwaway clone under /tmp that is deleted, so the fix
# object never enters /app/src/.git — it is unreachable there by design.
#
# The project's own regression tests for the bug (two QUnit cases in
# test/test-suite.js added by the fix commit) are extracted into
# /opt/golden/test-suite.js — the fix commit's whole test-suite.js — through
# that throwaway clone. They are NOT shipped in the tree the agent works in
# (the agent's suite is the pristine parent suite, which is fully green, so
# the agent must write its own reproduction from the symptom alone); the
# verifier overlays the golden suite onto the agent's repaired tree and runs
# the project's own jsdom test runner.
#
# A build-time smoke run overlays the golden suite onto the working tree and
# requires exactly the mined failure (the own-accessor clobber case fails with
# the armed `onerror` surviving), then reverts the file — proving the image
# ships the mined failing state and the golden extraction works.
#
# DOMPurify is not a Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json), so cloning it is allowed.
FROM bench-base:node-22

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=2c8ca25ef3cec05e12a50bd456f57a816eaa5998
ARG FIX_SHA=0332fe7cd45ad7971935e78c210c4714be4662ad
ARG GOLDEN_SHA=52b94a4e66224f758a8b5785d57060c00009b282e4c0f66ad6d8b447851a831c

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
RUN mkdir -p /app/src \
 && cd /app/src \
 && git init -q \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch -q --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- pinned dependencies (committed lockfile; jsdom 29.1.1) -----------------
RUN cd /app/src && npm ci --no-audit --no-fund --no-progress

# ---- extract the upstream regression tests from the FIX commit --------------
# Throwaway clone under /tmp, removed afterwards; the fix commit never exists
# inside /app/src/.git.
RUN mkdir -p /opt/golden \
 && git init -q /tmp/goldensrc \
 && cd /tmp/goldensrc \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch -q --depth 1 origin "$FIX_SHA" \
 && git show "$FIX_SHA":test/test-suite.js > /opt/golden/test-suite.js \
 && test "$(sha256sum /opt/golden/test-suite.js | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && grep -q "a clobbered ownerDocument does not skip the fail-closed scrub" \
      /opt/golden/test-suite.js \
 && cd / && rm -rf /tmp/goldensrc

# ---- build-time smoke: the golden suite must FAIL on the buggy parent tree ----
# in exactly the mined way: the own-accessor clobber regression fails because
# the armed `onerror` handler survives the aborted in-place scrub, and the
# engine-dependent "natural child" regression still passes. The pristine
# parent suite itself is fully green (1203/1203 as of this pin). The overlay
# is reverted afterwards so the agent starts with the untouched tree.
RUN cd /app/src \
 && cp /opt/golden/test-suite.js test/test-suite.js \
 && bash -c 'set +e; \
      node test/jsdom-node-runner > /tmp/smoke.log 2>&1; \
      rc=$?; \
      set -e; \
      test "$rc" -ne 0; \
      test "$(grep -cE "^[[:space:]]*not ok" /tmp/smoke.log)" -eq 1; \
      grep -q "armed on\* handler stripped despite the ownerDocument clobber" /tmp/smoke.log; \
      grep -q "got: \"alert(1)\"" /tmp/smoke.log; \
      grep -q "form with a natural ownerDocument-clobbering child stays safe" /tmp/smoke.log' \
 && git checkout -- test/test-suite.js \
 && rm -f /tmp/smoke.log

ENV NODE_PATH=/app/src/node_modules \
    HOME=/tmp
WORKDIR /app

# The build ran as root; open the tree and the workdir for whichever uid the
# trial uses (the agent must edit sources, rebuild dist, and write /app/repro.js).
RUN chmod -R a+rwX /app/src /app
CMD ["/bin/bash"]