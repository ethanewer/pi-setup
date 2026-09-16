# sill-ember: expressjs/express — `res.location`/`res.redirect` fail with a
# 500 and no `Location` header when handed a WHATWG `URL` instance
# (upstream issue #5555, fixed by PR #5554, commit a003cfab034f...).
# The bug: the location helper takes its argument as-is (`var loc = url;`)
# and then calls `loc.toLowerCase()` on it, which throws a TypeError for a
# URL object. The fix converts the value with `String(url)` first.
#
# The image clones express SHALLOW at the PARENT commit (a1fa90fc...; the
# real upstream bug is present in the working tree), installs the project's
# dependency set so the whole reproduce/fix/verify loop runs offline, and
# extracts the project's OWN regression test for the bug (test/res.location.js
# as of the FIX commit) into /opt/golden at build time from a THROWAWAY clone
# that is deleted immediately afterwards. The fix commit is therefore never
# reachable from /app/src (the origin remote is removed from the trial clone
# as well). expressjs/express is not a Terminal-Bench 2.1 source repository
# (checked against specs/tb21_source_repositories.json).
ARG UPSTREAM_SHA_PARENT=a1fa90fcea7d8e844e1c9938ad095d62669c3abd
ARG UPSTREAM_SHA_FIX=a003cfab034fbadb1c78ae337ee8ab389adda217

FROM bench-base:node-22

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Working clone: the buggy PARENT commit, shallow, origin remote removed so
# the fix commit cannot be fetched from the trial clone. Only the parent
# commit ever exists in this object store.
# ---------------------------------------------------------------------------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && git remote remove origin \
 && rm -rf .git/refs/remotes .git/FETCH_HEAD

# ---------------------------------------------------------------------------
# Warm every dependency (runtime + dev, incl. mocha and supertest) so the
# reproduce/fix/verify loop is fully offline. Identical install command to
# the mining run. npm install ran as root, so open the tree for the
# uid-1000 agent in the SAME RUN (a separate chmod layer would duplicate
# every file's bytes in the image).
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && npm install --no-audit --no-fund > /tmp/npm-install.log 2>&1 \
 && test -x node_modules/.bin/mocha \
 && echo "npm install OK; mocha $(node_modules/.bin/mocha --version 2>/dev/null || true)" \
 && chmod -R a+rwX /app/src \
 && chmod a+rwX /app

# ---------------------------------------------------------------------------
# Golden regression test: the project's OWN test file for this bug as of the
# FIX commit, extracted from a THROWAWAY clone that is deleted immediately
# afterwards, so upstream test bytes never land in this task tree and the
# fix commit never lands in /app/src.
# ---------------------------------------------------------------------------
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:test/res.location.js > /opt/golden/res.location.js \
 && test "$(sha256sum /opt/golden/res.location.js | cut -d' ' -f1)" = "42b13505a3cce2ed8b4c3921beb6fb99d800034754d2ce8080ef9df7cf7aa35c" \
 && grep -q "should accept an instance of URL" /opt/golden/res.location.js \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# ---------------------------------------------------------------------------
# Pin the built node_modules contents so the verifier can detect any
# tampering with mocha/supertest (a hostile tree must not be able to fake
# the test harness). Computed in the same image that installs it, so it is
# always consistent with what the trial sees.
# ---------------------------------------------------------------------------
RUN ( find /app/src/node_modules -type f -print0 | sort -z | xargs -0 sha256sum; \
      find /app/src/node_modules -type l -printf '%p|%l\n' | sort ) \
    | sha256sum | cut -d' ' -f1 > /opt/node_modules.sha256 \
 && wc -c /opt/node_modules.sha256

# ---------------------------------------------------------------------------
# Smoke checks proving the shipped state is exactly the mined one:
#   (a) the fix commit is not reachable from the trial clone;
#   (b) a direct URL-object reproduction FAILS here (HTTP 500, no Location
#       header) -- the mined symptom;
#   (c) the project's own location test passes as shipped (9 passing);
#   (d) planting the golden regression test makes exactly the one added
#       case fail (9 passing / 1 failing), matching the mining observation.
# After (d) the tree is restored to the pristine parent state: the verifier
# plants the golden test itself at verify time.
# ---------------------------------------------------------------------------
COPY files/ /app/
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && (NODE_PATH=/app/src/node_modules node /app/smoke-repro.js > /tmp/smoke-repro.log 2>&1; rc=$?; \
     grep -q "REPRO-FAIL" /tmp/smoke-repro.log || { \
       echo "ERROR: repro did not fail with the mined symptom at parent (rc=$rc)"; \
       tail -20 /tmp/smoke-repro.log; exit 1; }; \
     echo "smoke: repro FAILS at parent as expected (rc=$rc)" ) \
 && ./node_modules/.bin/mocha --require test/support/env test/res.location.js > /tmp/smoke-mocha.log 2>&1 \
    || { echo "ERROR: shipped location test does not pass"; tail -20 /tmp/smoke-mocha.log; exit 1; } \
 && grep -q "9 passing" /tmp/smoke-mocha.log \
 && cp /opt/golden/res.location.js test/res.location.js \
 && ( ./node_modules/.bin/mocha --require test/support/env test/res.location.js > /tmp/smoke-golden.log 2>&1; \
      grc=$?; \
      grep -q "1 failing" /tmp/smoke-golden.log \
      && grep -q "9 passing" /tmp/smoke-golden.log \
      || { echo "ERROR: golden overlay did not fail in exactly the mined 1 case (rc=$grc)"; \
           tail -20 /tmp/smoke-golden.log; exit 1; }; \
      echo "smoke: golden overlay fails 1/9 as mined (rc=$grc)" ) \
 && git checkout -q -- test/res.location.js \
 && chmod a+rw test/res.location.js \
 && test -z "$(git status --porcelain)" \
 && rm -f /app/smoke-repro.js /tmp/smoke-repro.log /tmp/smoke-mocha.log /tmp/smoke-golden.log

WORKDIR /app

CMD ["/bin/bash"]