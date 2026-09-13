#!/bin/bash
# Verifier for capstan-mooring: proves the agent's fix in the real
# eslint/eslint tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit; every tracked file except the single replacement
# source file is byte-identical to it; no stray untracked files), (2)
# requiring /app/summary.md, (3) running the reproduction script, (4)
# planting the upstream project's own regression test for this bug
# (extracted from the fix commit at image build time into /opt/golden) and
# running it under the project's own runner (all 131 cases must pass), (5)
# running a targeted selection of the project's existing rule/rule-tester
# tests, and (6) running three authored hidden RuleTester cases that reach
# the same code path from inputs the upstream test does not use.
#
# Review hardening (independent reviewer): the whole grading loop also
# asserts the integrity of everything the loop depends on but that the
# git-scope check cannot see:
#   * node_modules is gitignored, so a tree that "passes" the scope check
#     could still be graded through tampered code if the parser or the test
#     runner were patched there. We (a) lock node_modules read-only in the
#     image, (b) compare the full tree against the sha256 manifest recorded
#     at image build time (`/opt/node_modules.sha256`, generated from the
#     very bytes the trial uses), and (c) additionally tripwire the parser
#     and runner entrypoints with embedded sha256 constants so a forged
#     manifest cannot hide a swap.
#   * /opt/golden, /app/repro.js and the hidden-case scripts are all
#     re-asserted against pinned sha256 constants before use, so tampering
#     with any of them cannot neutralise a step.
#   * an inline copy of the reproduction is run as well, so the step cannot
#     be satisfied by editing /app/repro.js.
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

# Do not resolve through refs/replace objects: a replaced parent commit could
# otherwise feed the git provenance checks below a fake tree.
export GIT_NO_REPLACE_OBJECTS=1

PARENT=ad74a8dada2aaa17bfd0b8cc7b4119ff7a8ac04b
MOCHA=./node_modules/.bin/mocha

# Pinned sha256 constants. Every one of these bytes is generated from the
# task's own image at build time and is stable because espree/mocha are
# pinned in the Dockerfile and the rest is baked.
H_GOLDEN=52bf15fdce9f12b7d0d69fa98b134d8d673edfa1173471e91f4226b7875ba436
H_REPRO=3cd684c0bc92c29f33dbc074ec6b399f81bdd8bbbfd16c9eff5b1ebd98bd96ae
H_ESPREE_CJS=00ad93bce4a8af52aeaab7b8198c1ed072c9cf1b5cbb2d44e3d2fdc00562c059
H_ESPREE_JS=9ef1d03ec22b9b5cc2dc1ef43310a2bbf30ae750eb882cec9868eb5bda7d9186
H_ESPREE_LIB=713d844f758f5a947d703d50e7a50f16581bb19810e8c3f1f009b503ab1e12d5
H_MOCHA_BIN=93cde14427bcd0d250c4e6606f21713d100358f64a859f8bbc9ac6a195add2d2
H_MOCHA_M=cee3dbb8ff22b225b7c5bfcc305926701e79a198eb832c521e4ab74de27cc21b
H_HIDDEN_POSITIONS=2c865af008761d908e545dce0acf5838fc6a05eebcce4576b0f2580f022b4ac0
H_HIDDEN_SHAPES=6a63c8d95ca37ec1ccc5249dfa231d7dba6d2f1973fb9d16c43914b2b4e2fe0b
H_HIDDEN_STILL=0cee93ed64738b3a83c26e399d69513e3666de128a0e93830e028b741b856b0b

cd /app/src || fail "/app/src is missing"

# ---------------------------------------------------------------------------
# 0) environment integrity: the grading inputs the scope checks cannot see.
# ---------------------------------------------------------------------------
[ -f /opt/golden/no-loss-of-precision.js ] || fail "/opt/golden/no-loss-of-precision.js is missing"
[ "$(sha256sum /opt/golden/no-loss-of-precision.js | cut -d' ' -f1)" = "$H_GOLDEN" ] || fail "/opt/golden regression test is not the fix commit's test file (sha256 mismatch)"

[ -f /app/repro.js ] || fail "/app/repro.js is missing"
[ "$(sha256sum /app/repro.js | cut -d' ' -f1)" = "$H_REPRO" ] || fail "/app/repro.js has been modified (sha256 mismatch)"

for entry in \
    "node_modules/espree/dist/espree.cjs $H_ESPREE_CJS" \
    "node_modules/espree/espree.js $H_ESPREE_JS" \
    "node_modules/espree/lib/espree.js $H_ESPREE_LIB" \
    "node_modules/mocha/bin/mocha.js $H_MOCHA_BIN" \
    "node_modules/mocha/bin/_mocha $H_MOCHA_M"; do
    set -- $entry
    f=$1; want=$2
    [ -f "$f" ] || fail "parser/runner file missing: $f"
    got=$(sha256sum "$f" | cut -d' ' -f1)
    [ "$got" = "$want" ] || fail "parser/runner file modified: $f (sha256 mismatch)"
done

[ -f /opt/node_modules.sha256 ] || fail "/opt/node_modules.sha256 manifest is missing"
( cd /app/src/node_modules && find . -type f -print0 | xargs -0 sha256sum | LC_ALL=C sort ) > /tmp/node_modules.now
if ! cmp -s /tmp/node_modules.now /opt/node_modules.sha256; then
    echo "node_modules differs from the manifest recorded at build time:" >> "$LOG"
    diff /opt/node_modules.sha256 /tmp/node_modules.now | head -20 >> "$LOG"
    fail "node_modules was modified (see $LOG)"
fi

# ---------------------------------------------------------------------------
# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
# ---------------------------------------------------------------------------
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the file that implements the rule's precision-loss decision,
#    discovered by the agent, not named here). This is a CONTENT check, not
#    a git-status check: we hash the actual bytes of every tracked file on
#    disk against the pinned commit's own blob, so assume-unchanged/
#    skip-worktree tricks cannot hide a dirty file, and we refuse any
#    untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        lib/rules/no-loss-of-precision.js) : ;;
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
grep -qi "trailing" /app/summary.md || fail "/app/summary.md does not describe the bug"

# 4) the reproduction (the user-visible cases) must now pass: on the unfixed
#    tree this exits 1 with 'Should have no errors but had 1'. Run the
#    shipped script (immutable, see step 0) and an inline copy of it so a
#    modified /app/repro.js could not satisfy this step on its own.
if ! node /app/repro.js > /tmp/verifier-repro.log 2>&1; then
    tail -20 /tmp/verifier-repro.log >&2
    fail "reproduction script still reports errors (see /tmp/verifier-repro.log)"
fi
cat > /tmp/verifier-repro-inline.js <<'REPRO'
"use strict";

const rule = require(process.cwd() + "/lib/rules/no-loss-of-precision");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");

new RuleTester().run("no-loss-of-precision", rule, {
	valid: ["var x = 0."],
	invalid: [
		{
			code: "var x = 9007199254740993.",
			errors: [{ messageId: "noLossOfPrecision" }],
		},
	],
});
REPRO
if ! node /tmp/verifier-repro-inline.js > /tmp/verifier-repro-inline.log 2>&1; then
    tail -20 /tmp/verifier-repro-inline.log >&2
    fail "inline reproduction still reports errors (see /tmp/verifier-repro-inline.log)"
fi

# 5) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time; never part of this task tree; re-asserted
#    in step 0) and run it under the project's own runner. All 131 cases must
#    pass and the line must actually be printed (a neutralised run leaves no
#    summary).
cp /opt/golden/no-loss-of-precision.js tests/lib/rules/no-loss-of-precision.js || fail "cannot plant golden regression test"
[ "$(sha256sum tests/lib/rules/no-loss-of-precision.js | cut -d' ' -f1)" = "$H_GOLDEN" ] || fail "planted golden regression test does not match the fix commit's bytes"
if ! $MOCHA tests/lib/rules/no-loss-of-precision.js > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -qE "131 passing" /tmp/golden.out || {
    tail -30 /tmp/golden.out >&2
    fail "golden regression test did not actually run 131 passing cases (see /tmp/golden.out)"
}

# 6) a targeted selection of the project's OWN existing tests (neighbouring
#    numeric-literal rule tests plus the rule tester itself) must stay green.
EXISTING="tests/lib/rule-tester/rule-tester.js tests/lib/rules/no-magic-numbers.js tests/lib/rules/prefer-numeric-literals.js tests/lib/rules/no-octal-escape.js tests/lib/rules/radix.js tests/lib/rules/prefer-exponentiation-operator.js tests/lib/rules/no-new-native-nonconstructor.js tests/lib/rules/no-useless-call.js"
if ! $MOCHA $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing rule/rule-tester tests failed (see /tmp/existing.out)"
fi
grep -q "passing" /tmp/existing.out || fail "existing selection produced no passing summary (see /tmp/existing.out)"

# 7) three authored hidden cases: other inputs reaching the same decision
#    path that the upstream regression test does not use (trailing-dot
#    literals in other syntactic positions, unary-minus and numeric-separator
#    shapes, and still-lossy trailing-dot forms). Each drives the project's
#    own RuleTester and must exit 0. The scripts are re-asserted against
#    their pinned sha256 before they run, so none of them can be neutralised
#    between the agent's final state and this run.
if [ "$(sha256sum /tests/hidden/positions/run.js | cut -d' ' -f1)" != "$H_HIDDEN_POSITIONS" ] \
 || [ "$(sha256sum /tests/hidden/shapes/run.js | cut -d' ' -f1)" != "$H_HIDDEN_SHAPES" ] \
 || [ "$(sha256sum /tests/hidden/still-lossy/run.js | cut -d' ' -f1)" != "$H_HIDDEN_STILL" ]; then
    fail "hidden case script was modified (sha256 mismatch)"
fi

CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    script="$case/run.js"
    [ -f "$script" ] || fail "hidden case file missing: $script"
    : > "/tmp/hc-$name.out"
    ( cd /app/src && node "$script" ) > "/tmp/hc-$name.out" 2>&1
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