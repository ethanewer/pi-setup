# cistern-bridge: DOMPurify case-preserving attribute removal (upstream #1577
# family, parent of the fix). The image creates /app/src as a fresh repository
# that fetches ONLY the buggy parent commit, so the fix commit and any later
# tree that already contains the fix are absent from the object store, no refs
# exist, and - with no network at trial time - the answer cannot be fetched.
# The project's own regression tests for the defect are extracted from the fix
# commit at build time into /opt/golden/ (upstream bytes never enter this
# repository's tree) and a targeted golden module is derived from them.
#
# Node project: no compilation at trial time (dist/ is committed); the agent's
# fix is in the TypeScript source and is re-verified by rebuilding the
# committed dist artifact with the project's own build, then running the
# project's own jsdom test suite against that artifact.
FROM bench-base:node-22

ARG UPSTREAM_SHA=8cc5ae1388587f7a08cc099ff2a5e985f85d77c5
ARG FIX_SHA=083bb8aead7f6aba8cba30a9f954ade51f141c33

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: only the buggy parent commit is ever fetched -------------
# A brand-new repository fetching an exact SHA (GitHub serves reachable SHAs)
# pulls neither the default-branch tip - whose tree already contains this fix -
# nor the fix commit itself. After checkout the remote is removed, leaving a
# detachment with zero refs. Fail closed if the upstream SHA ever moves.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin \
 && test -z "$(git remote)" \
 && git config --system --add safe.directory '/app/src'

# ---- install (warm every cache; the trial is offline) ------------------------
ENV NODE_ENV=test \
    BABEL_ENV=rollup \
    PIP_NO_CACHE_DIR=1

RUN cd /app/src \
 && npm install --no-audit --no-fund \
 && git checkout -- package-lock.json \
 && test -z "$(git status --porcelain)"

# ---- golden: upstream regression tests for this defect, from the FIX commit --
# Throwaway bare clone, deleted immediately; the fix commit never exists inside
# /app/src/.git, so `! git cat-file -e ${FIX_SHA}^{commit}` keeps holding.
COPY files/extract-golden.sh /usr/local/bin/extract-golden.sh
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/cure53/DOMPurify.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test/test-suite.js > /opt/golden/test-suite.js \
 && test -s /opt/golden/test-suite.js \
 && grep -q 'uppercase event-handler attribute on a node is removed' /opt/golden/test-suite.js \
 && cd / && rm -rf /tmp/fixsrc \
 && extract-golden.sh \
 && rm /usr/local/bin/extract-golden.sh

WORKDIR /app
COPY files/ /app/

# harness-owned helpers run outside the runtime image
RUN rm -f /app/extract-golden.sh \
 && chmod -R a+rwX /app

CMD ["/bin/bash"]