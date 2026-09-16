#!/bin/bash
# Oracle for sill-ember: applies the one-source-file fix to the real
# expressjs/express tree at /app/src (the location helper must stringify
# its argument before any string operation runs on it), writes the agent
# deliverables (/app/repro.js, /app/summary.md), then proves the work with
# the project's own machinery: the reproduction script (must exit 0) and
# the project's own regression test for the bug (test/res.location.js as of
# the fix commit, baked at /opt/golden; all 10 cases must pass under mocha).
# Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the one-line stringify fix"

cp /solution/oracle-repro.js /app/repro.js
chmod a+rwx /app/repro.js
echo "oracle: wrote /app/repro.js"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the response helpers that set a redirect target (res.location and the
redirect helper built on it) fail with an HTTP 500 and no Location header
when handed a non-string location value such as a WHATWG URL object built
with the global URL constructor. Any application that computes its redirect
targets as URL objects was broken.

Cause: the location helper ran a string-only operation (lowercasing) on its
argument before converting it: `var loc = url;` followed by
`loc.toLowerCase()`. A URL object has no toLowerCase, so the handler threw
a TypeError and the framework answered the request with 500 and no Location
header.

Fix: convert the argument to its string form up front (`var loc = String(url);`)
so URL instances (and any other coercible value) flow through the same
encoded-URL handling as plain-string locations. 'back' alias handling,
absolute-vs-relative encoding and every plain-string case behave exactly as
before.

Verification: /app/repro.js (a supertest reproduction passing a URL object
to res.location) exits 0; the project's own regression test for this bug
(the fix-commit version of test/res.location.js, planted from /opt/golden,
10 cases) passes under mocha, and a targeted selection of the project's
existing res.* tests stays green.
MD
echo "oracle: wrote /app/summary.md"

# Prove the user-visible symptom is fixed.
NODE_PATH=/app/src/node_modules node /app/repro.js > /tmp/oracle_repro.log 2>&1 || {
    echo "oracle: repro still fails (see /tmp/oracle_repro.log)" >&2
    tail -20 /tmp/oracle_repro.log >&2
    exit 1
}
echo "oracle: repro OK (exit 0)"

# Prove it with the project's own regression test (golden bytes from
# /opt/golden, already in the image), via the project's own test runner.
cp /opt/golden/res.location.js test/res.location.js
if ! ./node_modules/.bin/mocha --require test/support/env test/res.location.js > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "10 passing" /tmp/oracle_golden.log || {
    echo "oracle: golden test did not actually run 10 cases" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
}
echo "oracle: golden regression test green (10 passing)"

# Prove a targeted selection of the project's own existing response tests
# stays green.
if ! ./node_modules/.bin/mocha --require test/support/env test/res.redirect.js test/res.set.js test/res.type.js test/res.send.js test/res.json.js > /tmp/oracle_existing.log 2>&1; then
    echo "oracle: existing response tests failed; tail:" >&2
    tail -20 /tmp/oracle_existing.log >&2
    exit 1
fi
echo "oracle: existing response tests green"

# Leave the tree exactly as the verifier expects it: the golden test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- test/res.location.js || {
    echo "oracle: could not restore test/res.location.js" >&2
    exit 1
}
# After restoring the golden plant, the ONLY modification left must be the
# fix itself in lib/response.js (the file where the bug lives).
if [ "$(git status --porcelain)" != " M lib/response.js" ]; then
    echo "oracle: unexpected working-tree state after restore" >&2
    git status --porcelain >&2
    exit 1
fi

echo "oracle: fix applied, deliverables written, repro + golden + existing suite green"
exit 0