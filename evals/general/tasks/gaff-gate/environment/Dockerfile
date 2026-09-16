# gaff-gate — expressjs/express status-code validation task
#
# Clones the real expressjs/express repository at the frozen parent commit of
# the issue #4212 fix (express 5.0.0-beta.3 era, 2024-07) and warms node_modules
# at build time so nothing needs the network during the trial. The agent must
# localize a silently-accepted-invalid-status-code defect, author its own
# regression, and fix the tree. The golden regression tests (from the fix
# commit) are extracted at build time through a SEPARATE throwaway clone under
# /tmp that is deleted afterwards, so the fix object never enters the shipped
# repository; the shipped clone asserts `! git cat-file -e $FIX^{commit}`.
FROM bench-base:node-22

# The clones below are created by this build, so they are root-owned; record
# the git safe.directory exception system-wide (per /etc/gitconfig) so the
# trial works whichever uid the harness runs it as, and set a build committer
# identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Frozen upstream revision: parent of the issue #4212 fix.
#   parent ee40a881f5d8cb4ce71bc45262fde8e4b7640d05  (bug present)
#   fix    723b5451bbcbab69bc8ded50ccd6545a79b8fe64  (never fetched into /app/src)
# Both resolved from https://github.com/expressjs/express.git on 2026-09-13.
# The HEAD assertion makes a force-moved tag or a drifted history fail the
# build closed instead of silently swapping the project under the task.
ARG PARENT_SHA=ee40a881f5d8cb4ce71bc45262fde8e4b7640d05
ARG FIX_SHA=723b5451bbcbab69bc8ded50ccd6545a79b8fe64

WORKDIR /app/src
# The agent's tree: the real express repository AT the parent commit, so the
# bug is live in the tree the agent receives. --depth 1 fetch of the parent
# SHA only: the fix commit must not be reachable in this repo (asserted twice).
RUN git init -q /app/src \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin ee40a881f5d8cb4ce71bc45262fde8e4b7640d05 \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$PARENT_SHA" \
 && ! git cat-file -e "$FIX_SHA^{commit}" \
 && echo "PIN OK: $(git rev-parse HEAD); fix commit unreachable"

# Warm every dependency at build time (mocha, supertest, and the runtime tree)
# so the trial and the verifier run with no fetches. The parent package.json is
# the 5.0.0-beta.3 dependency set.
RUN npm install --no-audit --no-fund 2>&1 | tail -3

# Extract the project's own regression tests from the FIX commit through a
# SEPARATE throwaway clone under /tmp, then delete that clone, so the fix
# object never enters the shipped repository and can never be read from the
# agent's repo with git log/git show. The golden files land in /opt/golden and
# the verifier hash-pins them (see tests/test.sh), so tampering is caught.
RUN git init -q /tmp/golden \
 && cd /tmp/golden \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin 723b5451bbcbab69bc8ded50ccd6545a79b8fe64 \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && cp test/res.status.js test/res.sendStatus.js /opt/golden/ \
 && cd / \
 && rm -rf /tmp/golden

# Final fail-closed assertion: the shipped repository still must not contain
# the fix commit object after the golden extraction step above.
RUN cd /app/src \
 && test "$(git rev-parse HEAD)" = "$PARENT_SHA" \
 && ! git cat-file -e "$FIX_SHA^{commit}" \
 && echo "FINAL PIN OK; fix still unreachable in /app/src"

WORKDIR /app
COPY files/ /app/