#!/bin/bash
# Verifier for spindrift-trim: proves the agent's fix in the real gin tree at
# /app/src by (1) asserting the verifier's own trust anchors (exact go 1.26.8
# version, sha256 of the go binary and of the golden regression test), (2)
# asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this clone), (3) asserting scope (every tracked
# file EXCEPT render/data.go is byte-identical to the parent commit's own blobs;
# the only file the bug lives in must actually differ; no stray untracked
# files), (4) requiring /app/repro.sh and /app/summary.md, (5) wiping the shared
# build cache once so the whole module is recompiled from the DELIVERED
# sources, (6) planting the upstream project's own regression test for this bug
# (render_test.go extracted from the fix commit at image build time into
# /opt/golden, sha256-pinned) and running it, (7) running the ENTIRE
# pre-existing render package test suite (go test github.com/gin-gonic/gin/render)
# to prove nothing else broke, (8) running the agent's own reproduction against
# the repaired tree (must pass) and against a pristine pre-fix tree copied from
# /opt/prefix-src into an unpredictable /tmp path (must fail, with assertion
# evidence), and (9) running two authored hidden Go+ test cases that reach the
# same rendered-raw-data path from inputs the upstream regression test does not
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

export PATH=/usr/local/go/bin:$PATH
export GOMODCACHE=/opt/gocache/pkg/mod GOCACHE=/opt/gocache/build GOPATH=/opt/gocache GOENV=/opt/gocache/env

PARENT=db309081bc5c137b2aa15701ef53f7f19788da25
FIX=5c00df8afadd06cc5be530dde00fe6d9fa4a2e4a

# --- 0) trust anchors ---
if [ "$(go version 2>/dev/null)" != "go version go1.26.8 linux/amd64" ]; then
    fail "go toolchain is not go 1.26.8 (got: $(go version 2>&1))"
fi
if ! sha256sum -c /opt/pins/go.sha256 >/dev/null 2>&1; then
    fail "go binary sha256 mismatch (substituted toolchain?)"
fi
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1; then
    fail "golden regression test sha256 mismatch (tampered /opt/golden?)"
fi

# --- 1) provenance: tree still at the pinned parent, fix unreachable ---
cd /app/src || fail "/app/src is missing"
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# --- 2) scope: content check, not git-status check ---
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        render/data.go) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            case "$mode" in
                120000*)
                    have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true) ;;
                *)
                    have=$(git hash-object -- "$f" 2>/dev/null || true) ;;
            esac
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -40 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi
# The bug's file must actually have changed (an untouched tree fixes nothing).
want_data=$(git rev-parse "$PARENT:render/data.go" 2>/dev/null || true)
have_data=$(git hash-object -- render/data.go 2>/dev/null || true)
if [ -z "$want_data" ] || [ "$have_data" = "$want_data" ]; then
    fail "render/data.go is byte-identical to the parent commit -- the bug is unfixed"
fi

# --- 3) deliverables ---
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# --- 4) fresh compile from the DELIVERED sources ---
# One wipe of the shared build cache forces go to recompile the whole module
# from the tree as delivered, so a planted or stale cache artifact (e.g. from
# the agent's own session, keyed to sources that do not exist here) cannot
# survive, and the executed tests provably come from the agent's sources.
rm -rf "$GOCACHE"
rm -rf /tmp/verify-src
cp -a /app/src /tmp/verify-src || fail "cannot copy the delivered tree"
cp /opt/golden/render_test.go /tmp/verify-src/render/render_test.go \
    || fail "cannot plant the golden regression test"

# --- 5) upstream regression test (the project's own test for this bug) ---
if ! ( cd /tmp/verify-src && go test -v github.com/gin-gonic/gin/render \
        -test.run 'TestRenderData' > /tmp/verify_golden.log 2>&1 ); then
    tail -30 /tmp/verify_golden.log >&2
    fail "upstream regression test failed on the repaired tree (see /tmp/verify_golden.log)"
fi
grep -q '^ok' /tmp/verify_golden.log \
    || fail "golden run did not report a passing go test run (see /tmp/verify_golden.log)"
grep -q -- '--- PASS: TestRenderData (' /tmp/verify_golden.log \
    || fail "TestRenderData did not pass (see /tmp/verify_golden.log)"
grep -q -- '--- PASS: TestRenderDataContentLength/' /tmp/verify_golden.log \
    || fail "TestRenderDataContentLength did not pass (see /tmp/verify_golden.log)"

# --- 6) the whole pre-existing render package suite (nothing else broke) ---
if ! ( cd /tmp/verify-src && go test github.com/gin-gonic/gin/render \
        > /tmp/verify_full.log 2>&1 ); then
    tail -30 /tmp/verify_full.log >&2
    fail "render package suite failed on the repaired tree (see /tmp/verify_full.log)"
fi
grep -q '^ok' /tmp/verify_full.log \
    || fail "render package suite did not report ok (see /tmp/verify_full.log)"

# --- 7) the agent's own reproduction, both directions ---
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -20 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
grep -q '^ok' /tmp/repro_fixed.out \
    || fail "agent repro did not report a passing go run on the repaired tree (see /tmp/repro_fixed.out)"

# Pre-fix direction: pristine parent tree from /opt/prefix-src, copied into an
# unpredictable path so the reproduction cannot special-case the verifier.
prerun=$(mktemp -d /tmp/spt-pre.XXXXXX) || fail "cannot make pre-fix scratch dir"
cp -a /opt/prefix-src "$prerun/src" || fail "cannot build pre-fix tree copy"
if GIN_SRC="$prerun/src" bash /app/repro.sh > /tmp/repro_prefix.out 2>&1; then
    rm -rf "$prerun"
    echo "agent repro PASSED against the pre-fix tree (expected failure); stdout:" >> "$LOG"
    head -20 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
rm -rf "$prerun"
grep -q 'FAIL' /tmp/repro_prefix.out \
    || fail "pre-fix repro output shows no FAIL evidence (see /tmp/repro_prefix.out)"
grep -q 'expected:' /tmp/repro_prefix.out \
    || fail "pre-fix repro output lacks the assertion-mismatch evidence (see /tmp/repro_prefix.out)"

# --- 8) authored hidden cases (inputs the upstream test does not use) ---
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && TREE=/tmp/verify-src bash ./run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stdout/stderr:" >> "$LOG"
        head -25 "$work/stdout.txt" >> "$LOG"
        head -25 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected 2"

echo "PASS: provenance, fix-unreachable, scope, deliverables, fresh compile, upstream regression test, full render suite, repro both directions, hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0