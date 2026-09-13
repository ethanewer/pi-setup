# capstan-mooring: eslint/eslint rule `no-loss-of-precision` falsely flags
# literals written with a trailing decimal point and no fractional digits
# (upstream issue #21251, fixed upstream by commit 1e641c91...).
#
# The image clones eslint SHALLOW at the PARENT commit (ad74a8da...; the
# real upstream bug is present in the working tree), installs the project's
# dependency set so the whole reproduce/fix/verify loop runs offline, and
# extracts the project's OWN regression test for the bug (the rule's test
# file as of the FIX commit) into /opt/golden at build time from a THROWAWAY
# clone that is deleted immediately afterwards. The fix commit is therefore
# never reachable from /app/src (the origin remote is removed from the trial
# clone as well). eslint/eslint is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
ARG UPSTREAM_SHA_PARENT=ad74a8dada2aaa17bfd0b8cc7b4119ff7a8ac04b
ARG UPSTREAM_SHA_FIX=1e641c919fc1421493bf913feb607896982451a3

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
 && git remote add origin https://github.com/eslint/eslint.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && git remote remove origin \
 && rm -rf .git/refs/remotes .git/FETCH_HEAD

# ---------------------------------------------------------------------------
# Warm every dependency (runtime + dev, incl. mocha and espree) so the
# reproduce/fix/verify loop is fully offline. eslint ships no lock file; the
# tree's own .npmrc sets package-lock=false exactly as upstream CI does.
# Identical install command to the mining run.
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && npm install --no-audit --no-fund > /tmp/npm-install.log 2>&1 \
 && test -x node_modules/.bin/mocha \
 && npm install --no-save --no-audit --no-fund espree@11.2.0 mocha@11.8.0 >> /tmp/npm-install.log 2>&1 \
 && node -p -e "console.log('pinned espree ' + require('espree/package.json').version + ' mocha ' + require('mocha/package.json').version)" 2>/dev/null \
 && test "$(node -p -e "require('espree/package.json').version" 2>/dev/null)" = "11.2.0" \
 && test "$(node -p -e "require('mocha/package.json').version" 2>/dev/null)" = "11.8.0" \
 && echo "npm install OK; mocha $(node_modules/.bin/mocha --version 2>/dev/null || true)"

# npm install ran as root; the trial may run as uid 1000 and the agent must
# be able to edit sources under /app/src, so open the whole tree.
RUN chmod -R a+rwX /app/src

# ---------------------------------------------------------------------------
# Golden regression test: the project's OWN test file for this rule as of
# the FIX commit, extracted from a THROWAWAY clone that is deleted
# immediately afterwards, so upstream test bytes never land in this task
# tree and the fix commit never lands in /app/src.
# ---------------------------------------------------------------------------
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/eslint/eslint.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/lib/rules/no-loss-of-precision.js > /opt/golden/no-loss-of-precision.js \
 && test "$(sha256sum /opt/golden/no-loss-of-precision.js | cut -d' ' -f1)" = "52bf15fdce9f12b7d0d69fa98b134d8d673edfa1173471e91f4226b7875ba436" \
 && grep -q '"var x = 0."' /opt/golden/no-loss-of-precision.js \
 && grep -q 'code: "var x = 9007199254740993."' /opt/golden/no-loss-of-precision.js \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# ---------------------------------------------------------------------------
# Smoke checks proving the shipped state is exactly the mined one:
#   (a) the fix commit is not reachable from the trial clone;
#   (b) the repro script FAILS here (bug present) -- exit 1/2 counts;
#   (c) the project's own rule test passes as shipped (129 passing);
#   (d) planting the golden regression test makes exactly the two added
#       cases behave as mined (1 failing / 130 passing), failing case being
#       the valid 'var x = 0.'.
# After (d) the tree is restored to the pristine parent state: the verifier
# plants the golden test itself at verify time.
# ---------------------------------------------------------------------------
COPY files/ /app/
WORKDIR /app/src
RUN if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && node /app/repro.js > /tmp/smoke-repro.log 2>&1; rc=$?; \
    grep -q "Should have no errors but had 1" /tmp/smoke-repro.log || { \
      echo "ERROR: repro did not fail with the mined symptom at parent (rc=$rc)"; \
      tail -20 /tmp/smoke-repro.log; exit 1; }; \
    echo "smoke: repro FAILS at parent as expected (rc=$rc)" \
 && ./node_modules/.bin/mocha tests/lib/rules/no-loss-of-precision.js > /tmp/smoke-mocha.log 2>&1 \
    || { echo "ERROR: shipped rule test does not pass"; tail -20 /tmp/smoke-mocha.log; exit 1; } \
 && grep -q "129 passing" /tmp/smoke-mocha.log \
 && cp /opt/golden/no-loss-of-precision.js tests/lib/rules/no-loss-of-precision.js \
 && ( ./node_modules/.bin/mocha tests/lib/rules/no-loss-of-precision.js > /tmp/smoke-golden.log 2>&1; \
      grc=$?; \
      grep -q "1 failing" /tmp/smoke-golden.log \
      && grep -q "130 passing" /tmp/smoke-golden.log \
      && grep -q "var x = 0." /tmp/smoke-golden.log \
      || { echo "ERROR: golden overlay did not fail in exactly the mined case (rc=$grc)"; \
           tail -30 /tmp/smoke-golden.log; exit 1; }; \
      echo "smoke: golden overlay fails 1/130 on 'var x = 0.' as mined (rc=$grc)" ) \
 && git checkout -q -- tests/lib/rules/no-loss-of-precision.js \
 && test -z "$(git status --porcelain)"

# ---------------------------------------------------------------------------
# Lock down node_modules so the rule-under-test cannot be bypassed by patching
# the parser or the test runner at trial time (node_modules is gitignored, so
# the tracked-file scope checks below cannot see changes inside it), and
# record a sha256 manifest of the whole tree for the verifier to replay.
# The manifest is generated HERE from the very bytes the trial will use, so
# it stays consistent across rebuilds; only espree/mocha are additionally
# pinned (above) because the verifier's embedded tripwire hashes for the
# parser/runner must be stable.
# ---------------------------------------------------------------------------
RUN cd /app/src/node_modules \
 && find . -type f -print0 | xargs -0 sha256sum | LC_ALL=C sort > /opt/node_modules.sha256 \
 && cd /app/src \
 && chmod -R a-w node_modules \
 && chmod -R a-w /opt/golden /opt/node_modules.sha256 \
 && echo "node_modules locked (a-w) and manifest recorded: $(wc -l < /opt/node_modules.sha256) files"

CMD ["/bin/bash"]