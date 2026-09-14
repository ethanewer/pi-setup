# hawser-quay: real-upstream debugging task against jestjs/jest, pinned to the
# parent commit of the fix for the "%j title + bigint row => TypeError: Do not
# know how to serialize a BigInt" regression (upstream issue #12827, fixed by
# PR #16338, fix commit 73f64cd2a234886060b089c8cf711ff2e75314d4).
#
# The image checks out the PARENT commit 30b0642f7c1a88b40e4d32726e8be0dee9dc0eb2
# so the agent gets the real tree with the real bug still present. The fix
# commit object is never fetched into /app/src; the project's own regression
# test (added by the fix) is extracted into /opt/hawser-golden through a
# throwaway clone that is deleted immediately.

ARG UPSTREAM_SHA=30b0642f7c1a88b40e4d32726e8be0dee9dc0eb2
ARG UPSTREAM_SHA_FIX=73f64cd2a234886060b089c8cf711ff2e75314d4

FROM bench-base:node-22

ARG UPSTREAM_SHA
ARG UPSTREAM_SHA_FIX

ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# --- 1. the real upstream tree, at exactly the parent commit ----------------
# `git init` + one depth-1 fetch of the pinned SHA keeps the object store in
# /app/src down to a single commit: the fix commit is never fetched here, so
# it cannot be read with `git log --all` or `git cat-file` at trial time.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && chmod -R a+rwX /app/src \
 && echo "parent tree ok: $(du -sh /app/src | cut -f1)"

# --- 2. pinned standalone toolchain (exact versions resolved 2026-09-13) ----
# The parameterised-title formatter module (table formatter + interpolation
# helper) compiles standalone with these; no monorepo build is needed.
RUN mkdir -p /opt/jest-deps && cd /opt/jest-deps \
 && npm install --no-audit --no-fund \
      typescript@7.0.2 \
      @types/node@22.20.2 \
      @jest/get-type@30.5.0 \
      pretty-format@30.5.1 \
      @jest/types@30.5.1 > /tmp/npm.log 2>&1 \
 && test -x node_modules/.bin/tsc \
 && node -e "const l=require('/opt/jest-deps/package-lock.json'); \
      for (const k of ['node_modules/typescript','node_modules/@types/node', \
                       'node_modules/@jest/get-type','node_modules/pretty-format', \
                       'node_modules/@jest/types']) { \
        const v=l.packages[k]?.version; if (!v) throw new Error('unpinned '+k); \
        console.log('pin', k, v); }"

# --- 3. pristine pre-fix copy of the formatter module ------------------------
# Read-only reference the verifier uses to prove the agent's own reproduction
# fails against the pre-fix code (the 'pre-fix tree concept' run).
RUN mkdir -p /opt/hawser-pristine/table \
 && cp /app/src/packages/jest-each/src/table/array.ts /opt/hawser-pristine/table/array.ts \
 && cp /app/src/packages/jest-each/src/table/interpolation.ts /opt/hawser-pristine/table/interpolation.ts \
 && sha256sum /opt/hawser-pristine/table/array.ts /opt/hawser-pristine/table/interpolation.ts

# --- 4. golden regression test, extracted from the FIX commit ---------------
# Separate throwaway clone under /tmp, deleted immediately afterwards, so the
# fix commit never lands in /app/src and upstream test bytes never land in the
# task tree. Only the project's OWN test file (packages/jest-each/src/__tests__
# /array.test.ts at the fix commit) is taken.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/jestjs/jest.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/hawser-golden \
 && git show ${UPSTREAM_SHA_FIX}:packages/jest-each/src/__tests__/array.test.ts \
      > /opt/hawser-golden/array.test.ts \
 && test -s /opt/hawser-golden/array.test.ts \
 && grep -q "title containing bigint param values" /opt/hawser-golden/array.test.ts \
 && grep -q "title containing a cyclic %j param value" /opt/hawser-golden/array.test.ts \
 && grep -q "param values holding replacement patterns" /opt/hawser-golden/array.test.ts \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# --- 5. golden runner: executes the three regression tests from the fix -----
# commit against a compiled formatter module directory (arg 1). Port of the
# three upstream assertions; generated here at build time so the pristine
# upstream test bytes stay out of the task tree. The SAME authored script is
# shipped at tests/golden/run-golden.sh and it is that read-only /tests copy
# the verifier executes at trial time: the trial agent is root in the same
# container as the verifier, so the /opt copy below is only a build-time
# probe artifact and oracle self-check helper, never a security boundary.
RUN cat > /opt/hawser-golden/run-golden.sh <<'SH'
#!/bin/bash
# Golden regression runner for hawser-quay.
#
# This is the AUTHORED hero-port of the three regression tests that the
# upstream jest fix (fix(jest-each): serialize bigint values in %j titles,
# PR #16338, commit 73f64cd) added to packages/jest-each/src/__tests__/
# array.test.ts, plus a few pre-existing formatter behaviours. The upstream
# test file itself is extracted into /opt/hawser-golden/array.test.ts at image
# build time (byte-identical, verified) and is never vendored into this tree.
#
# This copy lives under tests/ (not /opt) so that the verifier executes it
# from the read-only /tests mount: a trial agent runs as root in the same
# container as the verifier, so anything under /opt is tamperable; anything
# under /tests is a read-only bind mount and is not.
#
# Usage: run-golden.sh <dir-with-array.js>
#   Runs the three regression tests added by the upstream fix (bigint %j
#   values, cyclic %j value, values holding $ replacement patterns) against
#   the compiled formatter module found at "$1/array.js", plus the
#   pre-existing formatter behaviours the fix must not break. Exit 0 only if
#   every title matches the upstream expectations exactly.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "GOLDEN: no array.js in $DIR"; exit 1; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let ok = true;
const check = (name, cond) => { if (!cond) { console.error('GOLDEN FAIL: ' + name); ok = false; } };

// (1) calls global test with title containing bigint param values
let t = array('expected string: %j %j %j %s', [[1n, {nested: 2n}, [3n], -4n]])
  .map(r => r.title);
check('bigint param values',
  JSON.stringify(t) === JSON.stringify(['expected string: "1n" {"nested":"2n"} ["3n"] -4n']));

// (2) calls global test with title containing a cyclic %j param value
const c = {}; c.self = c;
t = array('expected string: %j', [[c]]).map(r => r.title);
check('cyclic %j param value',
  JSON.stringify(t) === JSON.stringify(['expected string: [Circular]']));

// (3) calls global test with title containing param values holding replacement patterns
t = array('expected string: %p %p %j', [['$&', '$`', {nested: "$'" }]]).map(r => r.title);
check('replacement patterns render literally',
  JSON.stringify(t) === JSON.stringify(["expected string: \"$&\" \"$`\" {\"nested\":\"$'\"}"]))

// ---- the project's own EXISTING (pre-fix) regression tests, ported --------
// Ensures the repair broke none of the pre-existing formatter behaviours.
t = array('expected string: %s %p %s %p',
  [['string1', 'pretty1', 'string2', 'pretty2'],
   ['string1', 'pretty1', 'string2', 'pretty2']]).map(r => r.title);
check('existing %p at correct positions',
  JSON.stringify(t) === JSON.stringify(['expected string: string1 "pretty1" string2 "pretty2"',
                                        'expected string: string1 "pretty1" string2 "pretty2"']));

t = array('%s %s %s %s %s %s %s %s %s %s',
  [['hello', 1, null, undefined, 1.2, {foo: 'bar'}, ()=>{}, [],
    Number.POSITIVE_INFINITY, Number.NaN]]).map(r => r.title);
check('existing printf format',
  JSON.stringify(t) === JSON.stringify(["hello 1 null undefined 1.2 { foo: 'bar' } ()=>{} [] Infinity NaN"]));

t = array('expected index: %#', [{name: 'foo'}, {name: 'bar'}]).map(r => r.title);
check('existing %# index placeholder',
  JSON.stringify(t) === JSON.stringify(['expected index: 0', 'expected index: 1']));

t = array('expected string: %p %# $a $b $#', [{a: 'hello', b: 1}, {a: 'world', b: 1}]).map(r => r.title);
check('existing $variable mix',
  JSON.stringify(t) === JSON.stringify(["expected string: {\"a\": \"hello\", \"b\": 1} 0 $a $b $#",
                                        "expected string: {\"a\": \"world\", \"b\": 1} 1 $a $b $#"]));

t = array('expected escaped: %%e', [['x']]).map(r => r.title);
check('existing escaped placeholder',
  JSON.stringify(t) === JSON.stringify(['expected escaped: %e']));

if (!ok) { process.exit(1); }
console.log('GOLDEN: all 3 upstream regression tests + existing suite PASS');
JS
SH
RUN chmod 755 /opt/hawser-golden/run-golden.sh  && bash -n /opt/hawser-golden/run-golden.sh  && echo "golden runner syntax ok"

# --- 6. build-time fail-closed direction probe ------------------------------
# Compile the PRISTINE (pre-fix) module and run the golden runner against it:
# the golden set MUST fail there (at least the bigint case throws). This
# proves in every image build that the bug reproduces on this node runtime and
# that the golden regression test actually discriminates.
RUN mkdir -p /tmp/probe/src \
 && cp /opt/hawser-pristine/table/array.ts /opt/hawser-pristine/table/interpolation.ts /tmp/probe/src/ \
 && ln -s /opt/jest-deps/node_modules /tmp/probe/node_modules \
 && cd /tmp/probe \
 && /opt/jest-deps/node_modules/.bin/tsc --module commonjs --target es2022 \
      --esModuleInterop --skipLibCheck --outDir out src/array.ts src/interpolation.ts >/dev/null 2>&1; \
    test -f out/array.js || { echo "BUILD FAIL: pristine module did not compile"; exit 1; }; \
    bash /opt/hawser-golden/run-golden.sh /tmp/probe/out; rc=$?; \
    if [ "$rc" -eq 0 ]; then echo "BUILD FAIL: golden passed on PRISTINE pre-fix tree"; exit 1; fi; \
    echo "BUILD OK: golden regression test fails on pre-fix tree (rc=$rc) as required" \
 && node -e "try { require('node:util').format('%j', 1n); console.log('BUILD FAIL: bigint %j did not throw'); process.exit(1); } catch (e) { if (String(e.message).includes('BigInt')) { console.log('BUILD OK: bigint %j throws in this node'); } else { throw e; } }" \
 && rm -rf /tmp/probe

# --- 7. lock down the verifier's reference material -------------------------
# sha256 pins are diagnostics (a root agent could rewrite /opt and the pins
# together); the authoritative golden runner is the read-only /tests mount.
RUN mkdir -p /opt/pins \
 && cd /opt/jest-deps \
 && sha256sum node_modules/.bin/tsc node_modules/pretty-format/build/index.js \
      node_modules/@jest/get-type/build/index.js > /opt/pins/toolchain.sha256 \
 && sha256sum /opt/hawser-pristine/table/array.ts /opt/hawser-pristine/table/interpolation.ts \
      > /opt/pins/pristine.sha256 \
 && sha256sum /opt/hawser-golden/run-golden.sh /opt/hawser-golden/array.test.ts \
      > /opt/pins/golden.sha256 \
 && chmod 755 /opt/jest-deps /opt/hawser-pristine /opt/hawser-golden /opt/pins \
 && chmod 444 /opt/pins/*.sha256 /opt/hawser-pristine/table/*.ts /opt/hawser-golden/* \
 && chmod 644 /opt/jest-deps/package.json /opt/jest-deps/package-lock.json \
 && sha256sum -c /opt/pins/pristine.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && echo "pins ok"

# --- 8. workdir + agent files -------------------------------------------------
# Ownership/permissions of /app/src were set at the end of the clone RUN in
# the SAME layer (no second on-disk copy of the tree); only the small /app
# additions need chmod here.
WORKDIR /app
COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]