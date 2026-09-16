#!/bin/bash
# Verifier for shroud-bulkhead (upstream-clone bug-fix on aquasecurity/trivy:
# pnpm lockfile multi-document parsing).
#
# Reward is 1 only if ALL of the following hold:
#   1. deliverables exist: /app/repro.sh (executable) and /app/repro-fixture.yaml
#   2. the environment is untampered: git HEAD still the pinned parent commit,
#      the go tool is the pinned go1.26.3 binary, and working-tree changes are
#      confined to the pnpm lockfile module
#   3. the regression tests the tree shipped are untouched (byte digests match
#      the fix-commit originals), so skipping/editing them cannot pass
#   4. the whole pnpm lockfile module suite passes on the repaired /app/src
#   5. the agent's own reproducer FAILS against a pre-fix scratch copy (parser
#      sources restored to the pristine parent versions) and PASSES against
#      the repaired tree -- a reproducer that cannot discriminate scores 0
#   6. the same pre-fix scratch copy's module suite genuinely FAILS (the
#      pre-fix tree is really the buggy one, not merely "different")
#   7. every hidden case (fixtures the upstream regression test does not use)
#      parses correctly through the agent's repaired tree
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
failures=0
echo "== shroud-bulkhead verifier =="

PIN_SHA=a2777aed340e4bb11c6cea6d7cf5d4bf137587ec
GO_BIN_SHA256=d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65
# byte digests of the regression test files as they exist in the tree the
# image ships (extracted from the upstream fix commit at image build time)
GOLDEN_PARSE_TEST_SHA256=e0b2e070692d6f333ad700771c11faef99033b6174fc4fd345c760df12ff029e
GOLDEN_TESTCASE_SHA256=84a0ae7863da7a54a819005fbc0e61efb3a914381519dd80b3b867e6bc8cca09
GOLDEN_FIXTURE_SHA256=1c9731ae83a9433b2b12b48b4e9ba012404dd9f2d881ca7ae510e12263d29854

MOD=pkg/dependency/parser/nodejs/pnpm
SUITE="./$MOD/..."
REPRO=/app/repro.sh
FIXTURE_YAML=/app/repro-fixture.yaml
export PATH=/opt/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CGO_ENABLED=0 GOEXPERIMENT=jsonv2 GOMAXPROCS=1

cleanup() { rm -rf /tmp/sb-prefix /tmp/sb-repro /tmp/sb-hidden; }
trap 'cleanup' EXIT

# ---- 1. deliverables --------------------------------------------------------
if [ ! -x "$REPRO" ]; then
    echo "FAIL: deliverable $REPRO missing or not executable" >&2
    failures=1
fi
if [ ! -f "$FIXTURE_YAML" ]; then
    echo "FAIL: deliverable $FIXTURE_YAML missing" >&2
    failures=1
fi

# ---- 2. environment integrity ----------------------------------------------
if ! echo "$GO_BIN_SHA256  /opt/go/bin/go" | sha256sum -c - >/dev/null 2>&1; then
    echo "FAIL: /opt/go/bin/go is not the pinned go1.26.3 binary (tampered or wrapped)" >&2
    failures=1
fi
if [ "$(/opt/go/bin/go version 2>/dev/null)" != "go version go1.26.3 linux/amd64" ]; then
    echo "FAIL: 'go version' did not report the pinned go1.26.3 toolchain" >&2
    failures=1
fi
H=$(git -C /app/src rev-parse HEAD 2>/dev/null || true)
if [ "$H" != "$PIN_SHA" ]; then
    echo "FAIL: /app/src is not at the pinned parent commit (got $H)" >&2
    failures=1
fi
# the pristine parser sources the verifier uses to rebuild the pre-fix tree
# must still be the pinned commit's own blobs (an agent could otherwise
# launder a "pre-fix" tree that their reproducer passes on)
if ! { git -C /app/src show "$PIN_SHA:$MOD/parse.go" 2>/dev/null | diff -q - /app/.pristine/pnpm/parse.go >/dev/null 2>&1 \
   && git -C /app/src show "$PIN_SHA:$MOD/types.go" 2>/dev/null | diff -q - /app/.pristine/pnpm/types.go >/dev/null 2>&1; }; then
    echo "FAIL: /app/.pristine parser sources differ from the pinned commit's blobs" >&2
    failures=1
fi
# working-tree changes must be confined to the pnpm lockfile module
BAD=$(git -C /app/src status --porcelain 2>/dev/null | awk '{p=substr($0,4); if (p ~ /^pkg\/dependency\/parser\/nodejs\/pnpm(\/|$)/) next; print}' )
if [ -n "$BAD" ]; then
    echo "FAIL: changes outside the pnpm lockfile module:" >&2
    echo "$BAD" >&2
    failures=1
fi
# the module must be a real directory, not a symlink laundering the fix
# outside the tree
if [ "$(find /app/src/$MOD -type l 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "FAIL: symlinks inside $MOD are not allowed" >&2
    find /app/src/$MOD -type l 2>/dev/null | head -5 >&2
    failures=1
fi

# ---- 3. shipped regression tests untouched ----------------------------------
check_digest() {
    local file="$1" want="$2"
    if [ ! -f "/app/src/$file" ]; then
        echo "FAIL: regression test file /app/src/$file is missing" >&2
        return 1
    fi
    local got
    got=$(sha256sum "/app/src/$file" | awk '{print $1}')
    if [ "$got" != "$want" ]; then
        echo "FAIL: /app/src/$file was modified (digest $got != $want)" >&2
        return 1
    fi
    return 0
}
check_digest "$MOD/parse_test.go" "$GOLDEN_PARSE_TEST_SHA256" || failures=1
check_digest "$MOD/parse_testcase.go" "$GOLDEN_TESTCASE_SHA256" || failures=1
check_digest "$MOD/testdata/pnpm-lock_v9_multiple_documents.yaml" "$GOLDEN_FIXTURE_SHA256" || failures=1

# ---- 4. module suite must pass on the repaired tree -------------------------
(
    cd /app/src || exit 1
    go test -v -short "$SUITE" > /tmp/sb-suite.log 2>&1
)
RC=$?
if [ $RC -ne 0 ]; then
    echo "FAIL: pnpm module suite did not pass on /app/src (exit $RC)" >&2
    tail -25 /tmp/sb-suite.log >&2
    failures=1
else
    echo "suite: pnpm module suite PASSES on repaired tree"
fi

# ---- 5. the agent's reproducer must discriminate ----------------------------
# 5a. pre-fix tree: a scratch copy with the two parser sources restored to
#     their pristine parent-state versions (/app/.pristine, saved at build time)
if [ $failures -eq 0 ] && [ -x "$REPRO" ]; then
    if cp -a /app/src /tmp/sb-prefix 2>/dev/null; then
        cp /app/.pristine/pnpm/parse.go /tmp/sb-prefix/$MOD/parse.go
        cp /app/.pristine/pnpm/types.go /tmp/sb-prefix/$MOD/types.go
        if bash "$REPRO" /tmp/sb-prefix > /tmp/sb-repro-prefix.log 2>&1; then
            echo "FAIL: reproducer exited 0 on the PRE-FIX tree (it must fail there)" >&2
            tail -12 /tmp/sb-repro-prefix.log >&2
            failures=1
        else
            echo "repro: reproducer FAILS on the pre-fix tree (as required)"
        fi
    else
        echo "FAIL: could not stage the pre-fix tree" >&2
        failures=1
    fi
fi
# 6. sanity: the pre-fix scratch copy's own module suite must genuinely fail
if [ -d /tmp/sb-prefix ]; then
    ( cd /tmp/sb-prefix && go test -v -short "$SUITE" > /tmp/sb-prefix-suite.log 2>&1 )
    PRC=$?
    if [ $PRC -eq 0 ]; then
        echo "FAIL: pre-fix scratch tree passes its module suite; the 'buggy' tree is not actually buggy" >&2
        failures=1
    else
        echo "sanity: pre-fix tree module suite FAILS (bug present)"
    fi
fi
# 5b. repaired tree
if [ -x "$REPRO" ]; then
    if bash "$REPRO" /app/src > /tmp/sb-repro-fixed.log 2>&1; then
        echo "repro: reproducer PASSES on the repaired tree"
    else
        echo "FAIL: reproducer exited nonzero on the repaired tree" >&2
        tail -20 /tmp/sb-repro-fixed.log >&2
        failures=1
    fi
fi

# ---- 7. hidden cases ----------------------------------------------------------
HIDDEN_ROOT=/tests/hidden
if [ -d "$HIDDEN_ROOT" ]; then
    for case in "$HIDDEN_ROOT"/*/; do
        cname=$(basename "$case")
        [ -d "$case" ] || continue
        rm -rf /tmp/sb-hidden
        if ! cp -a /app/src /tmp/sb-hidden 2>/dev/null; then
            echo "FAIL: could not stage hidden case $cname" >&2
            failures=1
            continue
        fi
        tfile=$(ls "$case"/*_test.go 2>/dev/null | head -1)
        fxfile=$(ls "$case"/*.yaml 2>/dev/null | head -1)
        if [ -z "$tfile" ] || [ -z "$fxfile" ]; then
            echo "FAIL: hidden case $cname is missing its test/fixture payload" >&2
            failures=1
            continue
        fi
        cp "$tfile" "/tmp/sb-hidden/$MOD/$(basename "$tfile")"
        cp "$fxfile" "/tmp/sb-hidden/$MOD/testdata/$(basename "$fxfile")"
        runpat=$(grep -oE 'TestHidden[A-Za-z0-9_]*' "$tfile" | head -1)
        ( cd /tmp/sb-hidden && go test -v -short -run "$runpat" "$SUITE" > /tmp/sb-hidden.log 2>&1 )
        HC=$?
        if [ $HC -ne 0 ]; then
            echo "FAIL: hidden case $cname failed on the repaired tree (exit $HC)" >&2
            grep -E -- '--- (PASS|FAIL|BAD)|Error|FAIL' /tmp/sb-hidden.log | tail -12 >&2
            failures=1
        else
            echo "hidden: $cname PASSES on the repaired tree"
        fi
        rm -rf /tmp/sb-hidden
    done
else
    echo "FAIL: no hidden cases mounted" >&2
    failures=1
fi

# ---- 8. verdict --------------------------------------------------------------
if [ $failures -eq 0 ]; then
    echo "VERIFIER_OK: all checks passed"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER_FAILED: ${failures} check(s) failed" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0