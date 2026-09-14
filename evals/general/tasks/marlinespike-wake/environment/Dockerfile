# marlinespike-wake: upstream-clone bugfix task on prettier/prettier.
#
# Clones the REAL upstream repository at the PARENT commit of upstream fix
# #19687 (ea8167fcca3c446c4f689704dd8c12b52dd52100), installs the repository's
# dependencies, extracts the upstream regression fixtures for this bug from the
# FIX commit (8e05b371abe74a5e4e2c84121dd2fef01f564aec) into /opt/golden via a
# THROWAWAY clone that is deleted again, proves BOTH directions inside this
# image (bug reproduces at parent; golden test fails at parent and passes with
# the fix), and ships the buggy parent tree to the agent.
#
# Size hygiene: the whole tree under /app is created by and owned by uid 1000
# (user `node` in the base image) from the start, so there is no post-build
# `chown -R` copy-up layer; the npm cache goes to /tmp and is deleted in the
# same RUN.

ARG UPSTREAM_SHA_PARENT=ea8167fcca3c446c4f689704dd8c12b52dd52100
ARG UPSTREAM_SHA_FIX=8e05b371abe74a5e4e2c84121dd2fef01f564aec

FROM bench-base:node-22

WORKDIR /app

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Git safety + identity for both build-time and trial-time git operations.
# The trial runs in the same image (uid 1000 or root), so the system-wide
# safe.directory entry must exist before any git command runs.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Step 1: clone the REAL upstream repository at exactly the pinned parent
# commit. `git init` + one depth-1 fetch of the SHA means the object store in
# /app/src contains ONLY the parent commit; the fix commit is never fetched
# into this clone. Everything is created as uid 1000 (the base image's `node`
# user) so no chown copy-up layer is ever needed.
RUN install -d -o 1000 -g 1000 /app \
 && su -s /bin/bash node -c 'set -e; git init -q /app/src; cd /app/src; git remote add origin https://github.com/prettier/prettier.git; git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT}; git checkout -q --detach FETCH_HEAD; test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"; echo "cloned parent ${UPSTREAM_SHA_PARENT}"'

# Step 2: install the repository's dependencies (warm cache for the offline
# trial), as uid 1000, with the npm cache routed to /tmp and deleted in the
# same RUN (size hygiene). `--no-package-lock` keeps the tree byte-clean so
# the verifier's scope check sees exactly one changed source file in the end.
RUN su -s /bin/bash node -c 'set -e; cd /app/src; npm install --no-package-lock --no-audit --no-fund --cache /tmp/npm-cache > /tmp/npm-install.log 2>&1; tail -2 /tmp/npm-install.log; test -x node_modules/.bin/jest; [ -z "$(git status --porcelain)" ]; echo "npm install OK; git tree clean"' \
 && rm -rf /tmp/npm-cache /tmp/npm-install.log \
 && echo "npm cache removed"

# Step 3: extract the project's own regression fixtures for this bug from the
# FIX commit through a THROWAWAY clone under /tmp, removed in this same RUN,
# so the fix commit's objects never enter /app/src and the golden bytes never
# enter this task tree. The fix commit added one case to
# tests/format/scss/atrule/if-else.scss and updated its snapshot; both are the
# golden fixtures the verifier plants and runs with the project's own jest.
RUN set -e; \
    rm -rf /tmp/goldfix && mkdir -p /tmp/goldfix /opt/golden/atrule/__snapshots__; \
    cd /tmp/goldfix; \
    git init -q; \
    git remote add origin https://github.com/prettier/prettier.git; \
    git fetch --depth 1 origin ${UPSTREAM_SHA_FIX}; \
    git checkout -q --detach FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}"; \
    git show ${UPSTREAM_SHA_FIX}:tests/format/scss/atrule/if-else.scss > /opt/golden/atrule/if-else.scss; \
    git show ${UPSTREAM_SHA_FIX}:tests/format/scss/atrule/__snapshots__/format.test.js.snap > /opt/golden/atrule/__snapshots__/format.test.js.snap; \
    grep -q 'something == \$something-else and' /opt/golden/atrule/if-else.scss; \
    test -s /opt/golden/atrule/__snapshots__/format.test.js.snap; \
    cd /; rm -rf /tmp/goldfix; \
    chmod -R a+rX /opt/golden; \
    echo "golden fixtures extracted from fix commit (throwaway clone removed)"

# Step 4a: direction A+B -- with the dependency set installed in THIS image,
# the bug reproduces at the parent (CLI output leaves the operator dangling at
# end of line), and the golden at-rule test FAILS at the parent with the
# failing snapshot named `if-else.scss format 1`. The planted fixtures are
# restored afterwards so the shipped tree is pristine.
RUN set -e; \
    cp /opt/golden/atrule/if-else.scss /app/src/tests/format/scss/atrule/if-else.scss && \
    cp /opt/golden/atrule/__snapshots__/format.test.js.snap /app/src/tests/format/scss/atrule/__snapshots__/format.test.js.snap && \
    printf '@if $very-very-very-very-very-very-long-var == 0 and $very-very-very-long-var == 0 {}\n' > /tmp/cmin.scss && \
    node /app/src/bin/prettier.js /tmp/cmin.scss > /tmp/buggy.out && \
    grep -qE ' ==$' /tmp/buggy.out && \
    echo "direction A: bug reproduces at parent (dangling operator observed)" && \
    cd /app/src && \
    (node_modules/.bin/jest tests/format/scss/atrule/format.test.js --runInBand --ci > /tmp/golden-parent.log 2>&1; test $? -ne 0) && \
    grep -q 'if-else.scss format 1' /tmp/golden-parent.log && \
    echo "direction B: golden regression test FAILS at parent (if-else.scss format 1)" && \
    git checkout -- tests/format/scss/atrule/if-else.scss tests/format/scss/atrule/__snapshots__/format.test.js.snap && \
    test -z "$(git status --porcelain)" && \
    echo "tree restored to pristine parent"

# Step 4b: direction C+D -- with the authored fix patch applied (the same
# four-line change upstream made), the CLI output groups each comparison with
# its right operand and the golden at-rule test passes 5/5. The patch comes
# through the build context and is deleted again in this RUN, so the shipped
# image contains no readable copy of the fix.
COPY scripts/fix.patch /tmp/fix.patch
RUN set -e; cd /app/src; \
    git apply /tmp/fix.patch && \
    cp /opt/golden/atrule/if-else.scss tests/format/scss/atrule/if-else.scss && \
    cp /opt/golden/atrule/__snapshots__/format.test.js.snap tests/format/scss/atrule/__snapshots__/format.test.js.snap && \
    node /app/src/bin/prettier.js /tmp/cmin.scss > /tmp/fixed.out && \
    (grep -qE ' ==$' /tmp/fixed.out && { echo "ERROR: fix did not group comparisons"; exit 1; } || true) && \
    grep -q 'very-very-very-long-var == 0$' /tmp/fixed.out && \
    echo "direction C: with the fix, CLI output groups comparisons correctly" && \
    node_modules/.bin/jest tests/format/scss/atrule/format.test.js --runInBand --ci > /tmp/golden-fixed.log 2>&1 && \
    grep -q 'Tests:.*5 passed' /tmp/golden-fixed.log && \
    echo "direction D: golden regression test passes 5/5 with the fix" && \
    git checkout -- tests/format/scss/atrule/if-else.scss tests/format/scss/atrule/__snapshots__/format.test.js.snap && \
    git apply -R /tmp/fix.patch && \
    test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" && \
    test -z "$(git status --porcelain)" && \
    echo "fix reverted; tree is the pristine buggy parent again"; \
    rm -f /tmp/fix.patch /tmp/cmin.scss /tmp/buggy.out /tmp/fixed.out /tmp/golden-parent.log /tmp/golden-fixed.log; \
    echo "fix patch and scratch files removed from the image"

# Belt: prove the fix commit is NOT reachable from the trial clone (the agent
# must not be able to read the answer with `git log --all` or `git cat-file`).
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git log --all --oneline | wc -l)" = "1" \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; single-commit history confirmed"

# Step 5: drop the origin remote from the trial clone. Trials have public
# egress under current harbor defaults (reports/v42_wave.md section 9), so an
# agent that knows the repository URL could `git fetch origin <fix>` and read
# the answer from history; removing the remote removes even the URL from
# .git/config, and nothing at trial time (CLI, jest, verifier git ops) needs a
# remote.
RUN cd /app/src \
 && git remote remove origin \
 && test -z "$(git remote -v)" \
 && echo "origin remote removed from trial clone"

# Step 6: trust anchors for the verifier. Record sha256 of the golden
# fixtures and of the tool binaries the verifier executes, so a root-level
# adversarial agent cannot substitute a stub node/git or edited golden
# expectations and earn a fake pass. Readable by everyone (the verifier may
# run as root or uid 1000). The anchors file lists absolute paths, so
# `cd / && sha256sum -c /opt/pins/anchors.sha256` works from any cwd.
RUN set -e; NODEBIN=$(command -v node); GITBIN=$(command -v git); \
    mkdir -p /opt/pins && \
    sha256sum "$NODEBIN" "$GITBIN" /opt/golden/atrule/if-else.scss /opt/golden/atrule/__snapshots__/format.test.js.snap > /opt/pins/anchors.sha256 && \
    chmod -R a+rX /opt/pins && \
    sha256sum -c /opt/pins/anchors.sha256 >/dev/null && \
    echo "trust anchors pinned" && \
    cat /opt/pins/anchors.sha256

COPY files/ /app/
RUN chmod -R a+rX /app \
 && echo "task files copied"
# Note: environment/files/ deliberately contains no fixture code; everything
# the agent needs is the real upstream clone in /app/src plus the installed
# node_modules. The file shipped there is a provenance note only.

CMD ["/bin/bash"]