# tiller-fathom: prettier/prettier — Prettier drops the quotes from a
# TypeScript method literally named "new" inside an interface / object type,
# turning it into a construct signature and changing the meaning of the code
# (upstream issue #19621, fixed by upstream commit
# dd5e24eabeab1f75ad573c79781e5fd408bcfad3).
#
# The image clones prettier SHALLOW at the PARENT commit
# (c03ab4e71c23154d6b11537eee3c938f0d0f67d3; the real bug is present in the
# working tree), npm-installs the project's dependency set so the whole
# reproduce/fix/verify loop runs offline, and plants the project's OWN
# regression test for the bug (the issue-19618.ts fixture plus the snapshot
# entries the FIX commit adds to tests/format/typescript/quote-props) into
# the working tree from a THROWAWAY clone under /tmp that is deleted
# immediately afterwards. The fix commit object is therefore never reachable
# from /app/src nor /app/pristine.
# prettier/prettier is not a Terminal-Bench 2.1 source repository (verified
# against specs/tb21_source_repositories.json).
ARG UPSTREAM_SHA_PARENT=c03ab4e71c23154d6b11537eee3c938f0d0f67d3
ARG UPSTREAM_SHA_FIX=dd5e24eabeab1f75ad573c79781e5fd408bcfad3

FROM bench-base:node-22

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

# The trial may run as uid 1000; the clones are created by root.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Working clone: the buggy PARENT commit, pinned, shallow, on branch `work`.
# Origin is removed so the fix commit cannot be fetched from the trial clone;
# only the parent (plus the build-time "import regression test" commit) ever
# exists in this object store.
# ---------------------------------------------------------------------------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && git checkout -q -B work

# ---------------------------------------------------------------------------
# Golden regression test: the fixture and snapshot the FIX commit adds, copied
# in from a THROWAWAY clone of the fix commit. The throwaway clone is deleted
# in the same RUN, so the fix commit's objects never stay anywhere in the
# image. The files are committed on `work` so the trial tree starts clean;
# the verifier pins their hashes so regenerating or deleting them fails.
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && git init -q /tmp/fix-src \
 && cd /tmp/fix-src \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && cp tests/format/typescript/quote-props/issue-19618.ts /app/src/tests/format/typescript/quote-props/issue-19618.ts \
 && cp tests/format/typescript/quote-props/__snapshots__/format.test.js.snap /app/src/tests/format/typescript/quote-props/__snapshots__/format.test.js.snap \
 && cd /app/src \
 && git add tests/format/typescript/quote-props/issue-19618.ts tests/format/typescript/quote-props/__snapshots__/format.test.js.snap \
 && git commit -q -m "build: import upstream regression test for quoted new method" \
 && test -z "$(git status --porcelain)" \
 && git remote remove origin \
 && rm -rf .git/refs/remotes .git/FETCH_HEAD \
 && rm -rf /tmp/fix-src

# The fix commit must NOT exist in the shipped clone's object store, and the
# history must be exactly the parent plus the build-time import.
RUN cd /app/src \
 && ! git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} \
 && ! git cat-file -e ${UPSTREAM_SHA_FIX} \
 && test "$(git rev-list --count HEAD)" = "2" \
 && test "$(git rev-parse HEAD~1)" = "${UPSTREAM_SHA_PARENT}" \
 && git remote -v | wc -l | grep -qx "0"

# ---------------------------------------------------------------------------
# Dependencies: warm the full dependency set so the reproduce/fix/verify loop
# is offline. npm-install then open the tree for uid 1000 in the SAME RUN so
# the layer is written once (no copy-on-write duplication of node_modules).
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && npm install --no-audit --no-fund > /tmp/npm-install.log 2>&1 \
 && test -x node_modules/.bin/jest \
 && echo "npm install OK; jest $(node_modules/.bin/jest --version 2>/dev/null || true)" \
 && chmod -R a+rwX /app/src

# ---------------------------------------------------------------------------
# Pristine parent clone: a frozen pre-fix copy the verifier uses to check the
# agent's reproduction against the unmodified tree. Shares /app/src's
# node_modules by symlink (no duplicate layer). No golden files here.
# ---------------------------------------------------------------------------
RUN git init -q /app/pristine \
 && cd /app/pristine \
 && git remote add origin https://github.com/prettier/prettier.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git remote remove origin \
 && rm -rf .git/refs/remotes .git/FETCH_HEAD \
 && ln -s /app/src/node_modules node_modules \
 && chmod -R a+rwX /app/pristine

# Deliverable directory, writable by the trial user.
RUN install -d -m 0777 /app/repro

COPY files/ /app/