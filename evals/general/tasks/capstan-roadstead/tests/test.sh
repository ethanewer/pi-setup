#!/bin/bash
# Verifier for capstan-roadstead: proves the agent's fix in the real
# jestjs/jest tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit, the clone still contains exactly that one commit,
# the upstream fix commit is not reachable, every tracked file except the
# single source file where the bug lives is byte-identical to the parent
# blobs, and nothing untracked was left in the tree), (2) requiring
# /app/summary.md, (3) running the reproduction script (must print
# 'true false' and exit 0), (4) planting the project's OWN regression test
# for this bug (extracted from the fix commit at image build time into
# /opt/golden) and running it under the published jest test runner against
# the agent's edited tree sources -- all 10 cases must pass, (5) running
# two of the project's own existing jest-util test files (isPromise,
# formatTime) the same way, and (6) running three authored hidden cases
# that reach the same code path from globs/options the upstream test does
# not use. Reward is binary and written on every exit path (trap below).
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

PARENT=69b089574f10e607a93ad1b3eb56b4876e2a43fb
FIX=4a65c5aa40e31cd0aa377c33540891bc03572b16
TS=/opt/tsapp
SRC=/app/src
SRCSRC="$SRC/packages/jest-util/src"
GOLDEN=/opt/golden/globsToMatcher.test.ts
TSC="$TS/node_modules/.bin/tsc"
JEST="$TS/node_modules/.bin/jest"

# ---- run_case LABEL TESTFILE EXPECT_REGEX SRC_FILE... -----------------------
# Copies the named tree source files plus TESTFILE into a scratch layout
# mirroring the repository (sources at the root, test in __tests__/), type
# checks, and runs jest. Fails the verifier unless jest exits 0 and the
# summary matches EXPECT_REGEX.
run_case() {
    label=$1; tf=$2; expect=$3; shift 3
    RUN=$(mktemp -d /tmp/vcase.XXXXXX)
    mkdir -p "$RUN/__tests__"
    for s in "$@"; do
        cp "$SRCSRC/$s" "$RUN/" || { rm -rf "$RUN"; fail "run_case $label: cannot copy $SRCSRC/$s"; }
    done
    cp "$TS/tsconfig.json" "$TS/jest.config.json" "$RUN/"
    ln -s "$TS/node_modules" "$RUN/node_modules"
    cp "$tf" "$RUN/__tests__/$(basename "$tf")" || { rm -rf "$RUN"; fail "run_case $label: cannot copy $tf"; }
    if ! ( cd "$RUN" && "$TSC" -p tsconfig.json ) > /tmp/vcase-tsc.out 2>&1; then
        tail -30 /tmp/vcase-tsc.out >&2
        rm -rf "$RUN"
        fail "run_case $label: type check of the tree sources failed"
    fi
    if ! ( cd "$RUN" && "$JEST" out/__tests__/ ) > /tmp/vcase-jest.out 2>&1; then
        echo "--- jest output ($label) ---" >> "$LOG"
        tail -40 /tmp/vcase-jest.out >> "$LOG"
        rm -rf "$RUN"
        fail "run_case $label: jest reported failures (see $LOG)"
    fi
    if ! grep -qE "$expect" /tmp/vcase-jest.out; then
        echo "--- jest summary ($label) did not match '$expect' ---" >> "$LOG"
        tail -20 /tmp/vcase-jest.out >> "$LOG"
        rm -rf "$RUN"
        fail "run_case $label: expected jest summary '$expect' (see $LOG)"
    fi
    rm -rf "$RUN"
    echo "ok: run_case $label"
}

cd "$SRC" || fail "/app/src is missing"

# 1) tree provenance -----------------------------------------------------------
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
ncommits=$(git rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
    fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
fi
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        packages/jest-util/src/globsToMatcher.ts) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                # symlink blob: the blob bytes are the link target string;
                # compare blob OIDs (readlink without trailing newline)
                have=$(readlink -n "$f" 2>/dev/null | git hash-object --stdin || true)
            else
                # --no-filters: hash the raw bytes, defeating assume-unchanged
                # and text=auto clean filters (a pristine checkout is verbatim)
                have=$(git hash-object --no-filters -- "$f" 2>/dev/null || true)
            fi
            want=$(git ls-tree "$PARENT" -- "$f" | awk '{print $3}')
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
saw_mod=$(git hash-object --no-filters -- packages/jest-util/src/globsToMatcher.ts 2>/dev/null || true)
if [ "$saw_mod" = "$(git rev-parse $PARENT:packages/jest-util/src/globsToMatcher.ts 2>/dev/null)" ]; then
    fail "the deliverable /app/src is unchanged: the matcher source file equals the parent blob (no fix was implemented)"
fi
echo "ok: provenance -- pinned parent, one commit, single modified source file"

# 2) deliverable write-up -------------------------------------------------------
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -qi "dot" /app/summary.md || fail "/app/summary.md does not describe the bug"

# 3) the reproduction must now pass ---------------------------------------------
if ! bash /app/repro.sh > /tmp/verifier-repro.log 2>&1; then
    tail -20 /tmp/verifier-repro.log >&2
    fail "reproduction script still fails (see /tmp/verifier-repro.log)"
fi
grep -q "true false" /tmp/verifier-repro.log || {
    tail -20 /tmp/verifier-repro.log >&2
    fail "reproduction script did not print 'true false' (see /tmp/verifier-repro.log)"
}

# 4) the project's own regression test for this bug (golden bytes baked at
#    image build time; the upstream extension of the tree's own test file)
[ -s "$GOLDEN" ] || fail "golden regression test missing from image"
run_case golden "$GOLDEN" "Tests:[ ]*10 passed" globsToMatcher.ts replacePathSepForGlob.ts

# 5) two of the project's own existing jest-util test files must stay green
run_case existing-isPromise "$SRCSRC/__tests__/isPromise.test.ts" "Tests:" isPromise.ts
run_case existing-formatTime "$SRCSRC/__tests__/formatTime.test.ts" "Tests:" formatTime.ts

# 6) authored hidden cases: same code path, inputs the upstream test does
#    not use (dot flip in the opposite order, nocase flips, and an
#    interleaving of {dot: undefined}/{dot: false}/option-less calls)
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    for tf in "$case"/*.test.ts; do
        [ -f "$tf" ] || continue
        run_case "hidden-$name" "$tf" "Tests:" globsToMatcher.ts replacePathSepForGlob.ts
        CASES=$((CASES + 1))
    done
done
if [ "$CASES" -lt 3 ]; then
    fail "only $CASES hidden case file(s) ran; expected at least 3"
fi

echo "PASS: provenance, /app/summary.md, repro, golden regression test, existing jest-util tests, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0