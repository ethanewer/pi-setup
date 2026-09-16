# capstan-roadstead: jestjs/jest -- glob-matching options are silently
# ignored once a pattern has been seen (upstream issue #16381, fixed by
# commit 4a65c5aa40e31cd0aa377c33540891bc03572b16).
#
# The image clones jestjs/jest into /app/src and checks out the upstream
# PARENT commit 69b089574f10e607a93ad1b3eb56b4876e2a43fb (immediately
# before the fix), so the agent gets the real repository with the real bug
# still in it. The clone is created with `git init` + a single
# `git fetch --depth 1 origin <parent-sha>` and detached there, so the ONLY
# commit object in /app/src/.git is the parent itself: neither the fix
# commit nor any later history is reachable from /app/src, and
# `git rev-list --all --count` is exactly 1. The origin remote and
# FETCH_HEAD are removed afterwards, so the trial clone cannot fetch
# anything even if network existed (it does not: trials run with no
# network).
#
# The project's own regression test for the bug is extracted from the FIX
# commit at image build time into /opt/golden/ (upstream bytes never enter
# this repository), using a throwaway clone that is deleted immediately
# afterwards.
#
# The suite's tests are run with the project's own test runner (jest): a
# standalone compile/test toolchain at /opt/tsapp (typescript, picomatch
# 4.0.7, micromatch 4.0.8, jest 30.4.1 -- the same runtime versions the
# mining run used) compiles the tree's source files and the project's own
# test files, then runs them with the published jest binary.
#
# A build-time smoke run re-confirms BOTH directions inside this image:
# the golden regression test fails in exactly the four option-related
# cases (and the direct repro prints 'true true') against the buggy parent
# source, and passes 10/10 (repro prints 'true false') against the fix
# source. The fix source is scrubbed from the image after the smoke.
# ---------------------------------------------------------------------------
FROM bench-base:node-22

ARG UPSTREAM_PARENT=69b089574f10e607a93ad1b3eb56b4876e2a43fb
ARG UPSTREAM_FIX=4a65c5aa40e31cd0aa377c33540891bc03572b16

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && git remote remove origin \
 && rm -rf .git/refs/remotes .git/FETCH_HEAD

# ---- standalone compile/test toolchain (the trial runs fully offline) ------
RUN mkdir -p /opt/tsapp && cd /opt/tsapp \
 && printf '%s\n' \
  '{' \
  '  "name": "tsapp",' \
  '  "private": true,' \
  '  "dependencies": {"picomatch": "4.0.7", "micromatch": "4.0.8"},' \
  '  "devDependencies": {' \
  '    "typescript": "5.9.3",' \
  '    "@types/node": "18.14.1",' \
  '    "@types/picomatch": "4.0.0",' \
  '    "@types/micromatch": "4.0.10",' \
  '    "@types/jest": "30.0.0",' \
  '    "jest": "30.4.1"' \
  '  }' \
  '}' > package.json \
 && printf '%s\n' \
  '{' \
  '  "compilerOptions": {' \
  '    "module": "commonjs",' \
  '    "target": "es2022",' \
  '    "esModuleInterop": true,' \
  '    "skipLibCheck": true,' \
  '    "strict": true,' \
  '    "types": ["node", "jest"],' \
  '    "outDir": "out",' \
  '    "rootDir": "."' \
  '  },' \
  '  "include": ["*.ts", "__tests__/*.ts"]' \
  '}' > tsconfig.json \
 && printf '%s\n' \
  '{' \
  '  "rootDir": ".",' \
  '  "testMatch": ["**/*.test.js"],' \
  '  "testPathIgnorePatterns": ["/node_modules/"]' \
  '}' > jest.config.json \
 && npm install --no-audit --no-fund > /tmp/npm-install.log 2>&1 \
 && test -x node_modules/.bin/jest \
 && test -x node_modules/.bin/tsc \
 && echo "toolchain OK: jest $(node_modules/.bin/jest --version)"

# The agent (possibly uid 1000) edits sources under /app/src: open the tree.
RUN chmod -R a+rwX /app/src

# ---- golden regression test + fix source, from a throwaway clone ------------
# The fix commit object never lands inside /app/src/.git; it is fetched
# into /tmp/fixclone only, copied out as files, and that clone is deleted.
RUN git init -q /tmp/fixclone \
 && cd /tmp/fixclone \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_FIX} \
 && mkdir -p /opt/golden /tmp/fix-src \
 && git show ${UPSTREAM_FIX}:packages/jest-util/src/__tests__/globsToMatcher.test.ts \
      > /opt/golden/globsToMatcher.test.ts \
 && test "$(sha256sum /opt/golden/globsToMatcher.test.ts | cut -d' ' -f1)" \
      = "5ebeda7e2d55af028bf52e8c804ff7d1fd9134fd0ff89f5f3b8d611be6c782af" \
 && grep -q "works like micromatch when options are passed after the same glob was used without them" /opt/golden/globsToMatcher.test.ts \
 && grep -q "works like micromatch when the same glob is used with different options" /opt/golden/globsToMatcher.test.ts \
 && grep -q "works like micromatch when a glob is used without options after being used with them" /opt/golden/globsToMatcher.test.ts \
 && grep -q "works like micromatch when dot is passed as undefined" /opt/golden/globsToMatcher.test.ts \
 && git show ${UPSTREAM_FIX}:packages/jest-util/src/globsToMatcher.ts \
      > /tmp/fix-src/globsToMatcher.ts \
 && test "$(sha256sum /tmp/fix-src/globsToMatcher.ts | cut -d' ' -f1)" \
      = "edd2c6b08179788a8480e6dd4bd753b5f8f2a62581914705e2829f613dcae5f9" \
 && chmod a+r /opt/golden/globsToMatcher.test.ts \
 && cd / && rm -rf /tmp/fixclone

COPY files/ /app/
RUN chmod -R a+rwX /app

# ---- smoke: re-confirm BOTH directions inside this image --------------------
RUN bash /app/build-smoke.sh

WORKDIR /app
CMD ["/bin/bash"]