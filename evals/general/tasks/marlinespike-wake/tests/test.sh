#!/bin/bash
# Verifier for marlinespike-wake. Proves, on the real prettier tree at
# /app/src:
#   1. trust anchors: node/git binaries and the golden fixtures still match
#      the sha256 pins recorded at image build time (a root-level agent cannot
#      substitute a stub node/git or edited golden expectations);
#   2. provenance: HEAD is still the pinned parent commit, and every tracked
#      file except the single source file the fix needs is byte-identical to
#      the pinned tree (content hashes, not git status, so assume-unchanged
#      tricks cannot hide work); no stray untracked files;
#   3. deliverables: /app/summary.md and the agent's own reproduction
#      (/app/repro with input, expected and an executable check.sh);
#   4. the agent's reproduction FAILS on the pristine pre-fix tree (restored
#      from the pin) and PASSES on the repaired tree;
#   5. the upstream golden regression test for this bug (fixture + snapshot
#      extracted from the fix commit into /opt/golden at build time, pinned,
#      re-copied over the tree so edited tests cannot smuggle expectations)
#      passes via the project's own jest runner;
#   6. the project's own css+scss format suites stay green;
#   7. three authored hidden CLI cases that reach the same printer from inputs
#      the upstream test does not use.
# Also asserts the fix commit is not reachable from the trial clone.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=ea8167fcca3c446c4f689704dd8c12b52dd52100
FIX=8e05b371abe74a5e4e2c84121dd2fef01f564aec
ALLOWED_SRC=src/language-css/print/comma-separated-value-group.js
GIT=/usr/bin/git

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors.
if ! ( cd / && sha256sum -c /opt/pins/anchors.sha256 >/dev/null 2>&1 ); then
    fail "trust-anchor sha256 check failed (substituted node/git or golden fixtures)"
fi

# 1) provenance: still at the pinned parent commit; the fix commit must not be
#    reachable in this clone.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi
if "$GIT" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the trial clone"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (discovered by the agent, not named here). Content hashes against the
#    pinned commit's own blobs; refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$ALLOWED_SRC") : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | "$GIT" hash-object --stdin 2>/dev/null || true)
            else
                have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <("$GIT" ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <("$GIT" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -40 "$LOG"
    fail "working tree modified outside the single allowed source file (see $LOG)"
fi

# 3) deliverables.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
[ -f /app/repro/input.scss ] || fail "/app/repro/input.scss is missing"
[ -f /app/repro/expected.scss ] || fail "/app/repro/expected.scss is missing"
[ -f /app/repro/check.sh ] || fail "/app/repro/check.sh is missing"
[ -x /app/repro/check.sh ] || fail "/app/repro/check.sh is not executable"

# 4) the agent's own reproduction, run against the pristine pre-fix tree and
#    against the repaired tree. Restore the allowed source file to the pinned
#    parent (the scope check above guarantees that is the only difference),
#    require the reproduction to FAIL there; re-apply the agent's diff and
#    require it to PASS. A reproduction that passes on the pre-fix tree does
#    not target the bug; one that fails on the repaired tree is broken.
"$GIT" diff -- "$ALLOWED_SRC" > /tmp/agent.diff || fail "git diff failed"
"$GIT" checkout -- "$ALLOWED_SRC" || fail "could not restore $ALLOWED_SRC for pre-fix run"
if bash /app/repro/check.sh > /tmp/repro-prefix.out 2>&1; then
    echo "reproduction PASSED on the pristine pre-fix tree; it does not target the bug" >> "$LOG"
    tail -20 /tmp/repro-prefix.out >> "$LOG"
    "$GIT" apply /tmp/agent.diff 2>/dev/null
    fail "reproduction passes on the pre-fix tree (see $LOG)"
fi
"$GIT" apply /tmp/agent.diff || fail "could not re-apply the agent's diff"
if ! bash /app/repro/check.sh > /tmp/repro-fixed.out 2>&1; then
    tail -30 /tmp/repro-fixed.out >&2
    fail "reproduction failed on the repaired tree (see /tmp/repro-fixed.out)"
fi
if cmp -s /app/repro/input.scss /app/repro/expected.scss; then
    fail "reproduction expected output equals input; the repro is vacuous"
fi

# 5) the upstream golden regression test through the project's own runner.
cp /opt/golden/atrule/if-else.scss tests/format/scss/atrule/if-else.scss \
    || fail "cannot plant golden if-else.scss fixture"
mkdir -p tests/format/scss/atrule/__snapshots__ || fail "cannot create snapshot dir"
cp /opt/golden/atrule/__snapshots__/format.test.js.snap \
    tests/format/scss/atrule/__snapshots__/format.test.js.snap \
    || fail "cannot plant golden snapshot"
if ! node_modules/.bin/jest tests/format/scss/atrule/format.test.js --runInBand --ci \
        > /tmp/golden.out 2>&1; then
    tail -25 /tmp/golden.out >&2
    fail "golden regression test failed on the repaired tree (see /tmp/golden.out)"
fi
grep -q 'Tests:.*5 passed' /tmp/golden.out \
    || fail "golden at-rule run did not report 5 passing tests (see /tmp/golden.out)"

# 6) the project's own css/scss format suites (the changed printer serves the
#    css language family; if-else is part of scss and was verified in step 5).
if ! node_modules/.bin/jest tests/format/scss tests/format/css --runInBand --ci \
        > /tmp/suite.out 2>&1; then
    tail -25 /tmp/suite.out >&2
    fail "project css/scss format suites failed on the repaired tree (see /tmp/suite.out)"
fi

# 7) authored hidden CLI cases: other control-directive conditions reaching
#    the same printer from inputs the upstream test does not use. Each must
#    format byte-exactly to its expected output.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work" || fail "hidden case $name: cannot mkdir"
    cp "$case"input.scss "$work/input.scss" || fail "hidden case $name: missing input.scss"
    cp "$case"expected.scss "$work/expected.scss" || fail "hidden case $name: missing expected.scss"
    if ! node bin/prettier.js "$work/input.scss" > "$work/stdout.txt" 2> "$work/stderr.txt"; then
        echo "hidden case $name: prettier CLI exited non-zero; stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: prettier CLI exited non-zero (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected.scss"; then
        echo "hidden case $name: output mismatch; got:" >> "$LOG"
        head -25 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected at least 3"

echo "PASS: anchors, provenance, deliverables, repro both directions, golden regression test, css/scss suites, $CASES hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0