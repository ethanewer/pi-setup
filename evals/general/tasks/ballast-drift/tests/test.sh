#!/bin/bash
# Verifier for ballast-drift: proves the agent's fix in the real
# eslint/eslint tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit; every tracked file except the single replacement
# source file is byte-identical to it; no stray untracked files), (2)
# requiring /app/summary.md, (3) running the reproduction script, (4)
# planting the upstream project's own regression test for this bug
# (extracted from the fix commit at image build time into /opt/golden) and
# running it under the project's own runner (all 97 cases must pass), (5)
# running a targeted selection of the project's existing rule/rule-tester
# tests, and (6) running three authored hidden RuleTester cases that reach
# the same code path from inputs the upstream test does not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=2417cad57d7d1bc4cf3ecf0f0575cfb10ff2011c
MOCHA=./node_modules/.bin/mocha

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the file that implements the rule's capitalised-callee decision,
#    discovered by the agent, not named here). This is a CONTENT check, not
#    a git-status check: we hash the actual bytes of every tracked file on
#    disk against the pinned commit's own blob, so assume-unchanged/
#    skip-worktree tricks cannot hide a dirty file, and we refuse any
#    untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        lib/rules/new-cap.js) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # --no-filters: hash the raw bytes. (eslint's .gitattributes has
            # `* text=auto`, and one upstream docs blob contains a CRLF in the
            # middle of a file, so the clean-filtered hash would differ from the
            # pinned blob even on a pristine checkout.)
            have=$(git hash-object --no-filters -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverable: the agent's own change summary must exist and must actually
#    describe the bug it fixed.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -qi "UTC" /app/summary.md || fail "/app/summary.md does not describe the bug"

# 4) the reproduction (the three user-visible cases) must now pass: on the
#    unfixed tree this exits 1 with 'Should have no errors but had 1'. The
#    shipped repro script itself is pinned: a hostile agent could otherwise
#    satisfy this step by editing /app/repro.js instead of fixing the rule.
REPRO_SHA=$(sha256sum /app/repro.js | cut -d' ' -f1)
if [ "$REPRO_SHA" != "c115a4a0118d53e850d85462f9b7ae6819b9f432d0f0d52d2c3f8f92d244a3f4" ]; then
    fail "/app/repro.js was modified (sha256 $REPRO_SHA)"
fi
if ! node /app/repro.js > /tmp/verifier-repro.log 2>&1; then
    tail -20 /tmp/verifier-repro.log >&2
    fail "reproduction script still reports errors (see /tmp/verifier-repro.log)"
fi

# 5) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time; never part of this task tree) and run
#    it under the project's own runner. All 97 cases must pass and the line
#    must actually be printed (a neutralised run leaves no summary). The
#    planted bytes are pinned to the fix commit's own blob: /opt/golden is
#    writable by the agent, so a hostile tree could otherwise neutralise the
#    regression test instead of fixing the rule.
cp /opt/golden/new-cap.js tests/lib/rules/new-cap.js || fail "cannot plant golden regression test"
GOLDEN_SHA=$(sha256sum tests/lib/rules/new-cap.js | cut -d' ' -f1)
if [ "$GOLDEN_SHA" != "c373939d5ef63cd5c72fcc809735cd7fccf74102524c107ca3fe720f10eaefb9" ]; then
    fail "golden regression test is not the fix commit's blob (sha256 $GOLDEN_SHA)"
fi
if ! $MOCHA tests/lib/rules/new-cap.js > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -qE "97 passing" /tmp/golden.out || {
    tail -30 /tmp/golden.out >&2
    fail "golden regression test did not actually run 97 passing cases (see /tmp/golden.out)"
}

# 6) a targeted selection of the project's OWN existing tests (neighbouring
#    constructor/call-semantics rule tests plus the rule tester itself) must
#    stay green.
EXISTING="tests/lib/rules/new-parens.js tests/lib/rules/no-new.js tests/lib/rules/no-obj-calls.js tests/lib/rules/capitalized-comments.js tests/lib/rules/func-name-matching.js tests/lib/rules/constructor-super.js tests/lib/rules/no-new-native-nonconstructor.js tests/lib/rules/no-new-wrappers.js tests/lib/rules/no-useless-call.js tests/lib/rule-tester/rule-tester.js"
if ! $MOCHA $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing rule/rule-tester tests failed (see /tmp/existing.out)"
fi
grep -q "passing" /tmp/existing.out || fail "existing selection produced no passing summary (see /tmp/existing.out)"

# 7) three authored hidden cases: other inputs reaching the same decision
#    path that the upstream regression test does not use (deeper member
#    chains, computed member access, semantics-preservation controls). Each
#    drives the project's own RuleTester and must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    : > "/tmp/hc-$name.out"
    ( cd /app/src && node "$case/run.js" ) > "/tmp/hc-$name.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: node exited $rc; output:" >> "$LOG"
        head -20 "/tmp/hc-$name.out" >> "$LOG"
        fail "hidden case $name did not pass (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, repro, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0