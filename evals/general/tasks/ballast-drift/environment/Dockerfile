# ballast-drift: eslint/eslint rule `new-cap` false positive for `.UTC()`
# member calls when the rule is configured with `properties: false`
# (upstream issue #21275, fixed upstream by commit 8e2cb142217f2efee...).
#
# The image clones eslint SHALLOW at the PARENT commit (2417cad5...; the
# real upstream bug is present in the working tree), installs the project's
# dependency set so the whole reproduce/fix/verify loop runs offline, and
# extracts the project's OWN regression test for the bug (the rule's test
# file as of the FIX commit) into /opt/golden at build time from a THROWAWAY
# clone that is deleted immediately afterwards. The fix commit is therefore
# never reachable from /app/src (the origin remote is removed from the trial
# clone as well). eslint/eslint is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
ARG UPSTREAM_SHA_PARENT=2417cad57d7d1bc4cf3ecf0f0575cfb10ff2011c
ARG UPSTREAM_SHA_FIX=8e2cb142217f2efee1d10dcc02bfb75145ae775d

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
 && git show ${UPSTREAM_SHA_FIX}:tests/lib/rules/new-cap.js > /opt/golden/new-cap.js \
 && test "$(sha256sum /opt/golden/new-cap.js | cut -d' ' -f1)" = "c373939d5ef63cd5c72fcc809735cd7fccf74102524c107ca3fe720f10eaefb9" \
 && grep -q 'code: "foo.UTC();"' /opt/golden/new-cap.js \
 && grep -q 'code: "foo?.UTC();"' /opt/golden/new-cap.js \
 && grep -q 'code: "const b = a.Date.UTC();"' /opt/golden/new-cap.js \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# ---------------------------------------------------------------------------
# Smoke checks proving the shipped state is exactly the mined one:
#   (a) the fix commit is not reachable from the trial clone;
#   (b) the repro script FAILS here (bug present) -- exit 1/2 counts;
#   (c) the project's own rule test passes as shipped (94 passing);
#   (d) planting the golden regression test makes exactly the three added
#       cases fail (3 failing / 94 passing), matching the mining observation.
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
 && ./node_modules/.bin/mocha tests/lib/rules/new-cap.js > /tmp/smoke-mocha.log 2>&1 \
    || { echo "ERROR: shipped rule test does not pass"; tail -20 /tmp/smoke-mocha.log; exit 1; } \
 && grep -q "94 passing" /tmp/smoke-mocha.log \
 && cp /opt/golden/new-cap.js tests/lib/rules/new-cap.js \
 && ( ./node_modules/.bin/mocha tests/lib/rules/new-cap.js > /tmp/smoke-golden.log 2>&1; \
      grc=$?; \
      grep -q "3 failing" /tmp/smoke-golden.log \
      && grep -q "94 passing" /tmp/smoke-golden.log \
      || { echo "ERROR: golden overlay did not fail in exactly the mined 3 cases (rc=$grc)"; \
           tail -20 /tmp/smoke-golden.log; exit 1; }; \
      echo "smoke: golden overlay fails 3/94 as mined (rc=$grc)" ) \
 && git checkout -q -- tests/lib/rules/new-cap.js \
 && test -z "$(git status --porcelain)"

CMD ["/bin/bash"]