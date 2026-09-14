# stern-roadstead: real-upstream bugfix task on jestjs/jest (v4.2 family).
#
# The image ships the REAL jest monorepo checked out at the PARENT commit of
# upstream issue #16345 (a jest-each title-interpolation defect). It then
# builds the monorepo (yarn install + yarn build:js) so the whole iteration
# loop is offline and warm. The golden regression test (template.test.ts as
# of the FIX commit) is extracted through a throwaway clone into /opt/golden
# and sha256-pinned; the fix commit never enters the shipped /app/src.
FROM bench-base:node-22

WORKDIR /app

ARG UPSTREAM_SHA_PARENT=9ab14feccd6c15fec1334dbcb03a53a079d153d3
ARG UPSTREAM_SHA_FIX=74bd550d15e53b16e2970139da31d90f406b78c6

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The trial may run as uid 1000; git needs the repo marked safe and a committer
# identity for any build-time git operation.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the PARENT commit, shallowest
# possible: git init + one depth-1 fetch of the pinned SHA means the object
# store in /app/src holds ONLY the parent commit. The fix commit (which an
# agent must not be able to look up or fetch) is never fetched into this
# clone. chown happens in this same RUN so the tree is not duplicated into a
# later layer.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git log --oneline -1 \
 && chown -R 1000:1000 /app/src

# Extract the project's own regression test for this bug (the test the fix
# commit appends to packages/jest-each/src/__tests__/template.test.ts) into
# /opt/golden using a THROWAWAY clone that is deleted immediately afterwards,
# so the fix object never lands in /app/src and the golden bytes are pinned.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden /opt/pins \
 && git show ${UPSTREAM_SHA_FIX}:packages/jest-each/src/__tests__/template.test.ts > /opt/golden/template.test.ts \
 && test -s /opt/golden/template.test.ts \
 && grep -q "interpolates a heading that contains regex metacharacters" /opt/golden/template.test.ts \
 && echo "golden lines: $(wc -l < /opt/golden/template.test.ts)" \
 && sha256sum /opt/golden/template.test.ts > /opt/pins/golden.sha256 \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is NOT reachable from the shipped clone, and the
# golden clone is gone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test ! -e /tmp/upstream-fix-clone \
 && echo "fix commit unreachable from /app/src; golden clone removed"

# Warm everything the trial needs, offline: yarn 4 via corepack, the full
# workspace install (node_modules is the offline dependency cache), and the
# package build (yarn build:js), so an agent's iteration loop is seconds, not
# a build from scratch. chown at the END of this same RUN: the layer is
# written once, so the tree ownership does not double the image size.
RUN cd /app/src \
 && corepack enable \
 && yarn install --immutable \
 && yarn build:js \
 && chown -R 1000:1000 /app/src

# Replace the corepack shim with a direct wrapper onto the repo's VENDORED
# yarn release file, so `yarn` works offline for ANY user: corepack would
# otherwise try to download its own per-user copy of yarn 4.18.0 at trial
# time (the build ran as root, the trial may run as uid 1000 with an empty
# corepack cache and no network).
RUN printf '#!/bin/sh\nexec node /app/src/.yarn/releases/yarn-4.18.0.cjs "$@"\n' > /usr/local/bin/yarn \
 && chmod 755 /usr/local/bin/yarn \
 && yarn --version

# Everything the agent starts with (README-BUILD.md) lands in /app, owned by
# the trial user (uid 1000) so deliverables are writable in place. This chown
# is a no-op diff when the tree is already 1000-owned, so it adds no size.
COPY files/ /app/
RUN chown -R 1000:1000 /app

CMD ["/bin/bash"]