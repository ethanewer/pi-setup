#!/bin/bash
# Verifier for stern-roadstead: proves the agent's fix in the real jestjs/jest
# tree at /app/src by (1) asserting the verifier's own trust anchor (the
# golden regression test at /opt/golden still has the sha256 pinned at image
# build time), (2) asserting provenance and scope (HEAD is still the pinned
# parent commit, every tracked file except the single defect source file is
# byte-identical to it, no stray untracked files), (3) requiring /app/repro.sh
# and /app/summary.md, (4) forcing a fresh `yarn build:js` so compiled output
# reflects the agent's source, (5) executing the agent's OWN reproduction on
# the repaired tree (exact stdout + exit 0) and again with the defect source
# file swapped back to the parent version (it must genuinely fail there), (6)
# planting the project's own upstream regression test for this bug (extracted
# from the fix commit at image build time into /opt/golden, sha256-pinned) and
# running it with the project's own test runner, (7) running the project's own
# full jest-each unit suite, and (8) running three authored hidden cases that
# reach the same interpolation path from headings the upstream test does not
# use.
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

PARENT=9ab14feccd6c15fec1334dbcb03a53a079d153d3
FIX_FILE=packages/jest-each/src/table/interpolation.ts
export FORCE_COLOR=1
JEST="node ./packages/jest-cli/bin/jest.js"

cd /app/src || fail "/app/src is missing"

# 0) integrity anchor: the golden regression test in the image must still be
#    the bytes pinned at image build time.
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 > /dev/null 2>&1 ); then
    fail "golden test integrity check failed (substituted or tampered file)"
fi

# 1) provenance: the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD 2>/dev/null), expected pinned $PARENT"
fi

# 2) deliverables.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 3) scope: every tracked file must be byte-identical to the pinned commit
#    EXCEPT the single defect source file; no untracked non-ignored files.
#    Content-hash the actual bytes on disk (assume-unchanged/skip-worktree
#    tricks cannot hide a dirty file), and refuse any untracked file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$FIX_FILE") : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Symlinked tracked files must be hashed by their link target, not
            # by following the link.
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
            else
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
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
    fail "working tree modified outside the defect source file (see $LOG)"
fi

# Also confirm the agent did in fact change the defect file: a fully pristine
# tree would fail the reproduction steps below, so this is only a clearer
# diagnostic.
if [ "$(git hash-object -- "$FIX_FILE" 2>/dev/null)" = "$(git rev-parse "$PARENT:$FIX_FILE")" ]; then
    fail "$FIX_FILE is unchanged from the parent commit — the tree is untouched"
fi

# 4) fresh build so any compiled output reflects the agent's source.
rm -rf node_modules/.cache
if ! yarn build:js > /tmp/rebuild.log 2>&1; then
    tail -40 /tmp/rebuild.log >&2
    fail "yarn build:js failed on the agent's tree (see /tmp/rebuild.log)"
fi

# 5a) the agent's own reproduction must PASS on the repaired tree with the
#     exact stdout contract.
repro_out=$(/app/repro.sh 2>/tmp/repro.err)
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "repro.sh exited $rc on the repaired tree; stderr:" >> "$LOG"
    head -10 /tmp/repro.err >> "$LOG"
    fail "repro.sh exited $rc on the repaired tree (see $LOG)"
fi
if [ "$repro_out" != "rows: 1 is one
rows: 2 is two" ]; then
    echo "repro.sh stdout mismatch on the repaired tree; got:" >> "$LOG"
    printf '%s' "$repro_out" | od -c | head -8 >> "$LOG"
    fail "repro.sh stdout mismatch on the repaired tree (see $LOG)"
fi

# 5b) pre-fix concept: swap the defect file back to the parent version, rebuild
#     and re-run the agent's reproduction — it must GENUINELY fail there, or
#     the reproduction did not reproduce the bug. Then restore the agent's
#     file and rebuild again.
mv "$FIX_FILE" /tmp/agent-interpolation.ts || fail "cannot move agent's file aside"
git show "$PARENT:$FIX_FILE" > "$FIX_FILE" || { mv /tmp/agent-interpolation.ts "$FIX_FILE"; fail "cannot restore parent version"; }
rm -rf node_modules/.cache
if ! yarn build:js > /tmp/rebuild-prefix.log 2>&1; then
    mv /tmp/agent-interpolation.ts "$FIX_FILE"
    tail -40 /tmp/rebuild-prefix.log >&2
    fail "rebuild after pre-fix swap failed (see /tmp/rebuild-prefix.log)"
fi
repro_pre=$(/app/repro.sh 2>/tmp/repro-prefix.err)
rc_pre=$?
mv /tmp/agent-interpolation.ts "$FIX_FILE" || fail "cannot restore agent's file"
rm -rf node_modules/.cache
if ! yarn build:js > /tmp/rebuild-restore.log 2>&1; then
    tail -40 /tmp/rebuild-restore.log >&2
    fail "rebuild after restore failed (see /tmp/rebuild-restore.log)"
fi
if [ "$rc_pre" -eq 0 ] && [ "$repro_pre" = "rows: 1 is one
rows: 2 is two" ]; then
    fail "repro.sh also passed on the pre-fix tree — the reproduction does not exercise the bug"
fi
echo "pre-fix repro genuinely failed (rc=$rc_pre)" >> "$LOG"

# 6) the golden upstream regression test (from the fix commit, /opt/golden,
#    sha256-pinned) must pass with the project's own runner, and the new test
#    must actually have run. The tree's own test file is restored afterwards.
cp packages/jest-each/src/__tests__/template.test.ts /tmp/tree-template.test.ts
cp /opt/golden/template.test.ts packages/jest-each/src/__tests__/template.test.ts
if ! $JEST packages/jest-each/src/__tests__/template.test.ts --runInBand --verbose \
     > /tmp/golden.log 2>&1; then
    grep -m5 -A12 "●" /tmp/golden.log >&2
    mv /tmp/tree-template.test.ts packages/jest-each/src/__tests__/template.test.ts
    fail "golden regression test did not pass (see /tmp/golden.log)"
fi
mv /tmp/tree-template.test.ts packages/jest-each/src/__tests__/template.test.ts
seen=$(grep -c "interpolates a heading that contains regex metacharacters" /tmp/golden.log)
if [ "$seen" -lt 10 ]; then
    fail "golden regression test did not actually run (only $seen occurrences; see /tmp/golden.log)"
fi
echo "golden regression test passed (test seen $seen times)" >> "$LOG"

# 7) the project's own existing jest-each unit suite must stay green (the
#    tree's own test files as shipped at the parent commit).
if ! $JEST packages/jest-each/src/__tests__/array.test.ts \
     packages/jest-each/src/__tests__/index.test.ts \
     packages/jest-each/src/__tests__/template.test.ts \
     --runInBand --silent > /tmp/suite.log 2>&1; then
    tail -40 /tmp/suite.log >&2
    fail "the project's own jest-each unit suite failed (see /tmp/suite.log)"
fi
echo "existing jest-each unit suite green" >> "$LOG"

# 8) hidden cases: authored tests reaching the same interpolation path from
#    headings the upstream regression test does not use. Each is copied into
#    the tree, run with the project's own runner, and removed again.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    f=""
    for cand in "$case"/*.test.ts; do
        [ -f "$cand" ] && f=$cand && break
    done
    [ -n "$f" ] || fail "hidden case $name: no case.test.ts found"
    cp "$f" "packages/jest-each/src/__tests__/_hidden_${name}.test.ts" || fail "hidden case $name: cannot copy"
    if ! $JEST "packages/jest-each/src/__tests__/_hidden_${name}.test.ts" --runInBand --silent \
         > "/tmp/hidden-${name}.log" 2>&1; then
        tail -30 "/tmp/hidden-${name}.log" >&2
        rm -f "packages/jest-each/src/__tests__/_hidden_${name}.test.ts"
        fail "hidden case $name failed (see /tmp/hidden-${name}.log)"
    fi
    rm -f "packages/jest-each/src/__tests__/_hidden_${name}.test.ts"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected at least 3"

# 9) final cleanliness: git status may now show only the defect source file as
#    modified, nothing else (no leftovers from the verifier's own planting).
leftover=$(git status --porcelain | grep -v "^ M $FIX_FILE$" || true)
if [ -n "$leftover" ]; then
    printf '%s\n' "$leftover" >> "$LOG"
    fail "tree not clean after verification (see $LOG)"
fi

echo "PASS: provenance, scope, repro (fixed + pre-fix), golden regression test, existing suite, hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0