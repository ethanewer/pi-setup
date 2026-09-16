#!/bin/bash
# Verifier for ballast-brackish (upstream-clone soundness bugfix against the
# real Z3Prover/z3 tree). Checks, in order:
#   1. /app/src is the real Z3 clone with a warm build,
#   2. provenance: HEAD is still the pinned parent commit; the working tree
#      has no untracked files; exactly one tracked file differs and it is
#      the single source file a correct fix needs (src/ast/rewriter/
#      seq_rewriter.cpp), and that file really differs (a fix is present),
#   3. deliverable /app/summary.md exists and is non-empty,
#   4. the project's OWN regression test for this bug (baked at /opt/golden,
#      the fix-commit file with its answer-bearing prose comments stripped,
#      extracted at image-build time) is planted into src/test/seq_rewriter.cpp,
#      test-z3 is rebuilt offline, and the full sequence-rewriter module
#      (`test-z3 seq_rewriter`, including the 26 pre-existing tests) passes,
#   5. every hidden SMT2 case in /tests/hidden/* is run through the
#      agent-built /app/src/build/z3 and the exact verdict (sat/unsat) is
#      required, catching a spurious-unsat regression on inputs the upstream
#      test does not use and a reversed verdict on a genuinely inconsistent
#      formula.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

PARENT_SHA=5fcd89bf8c4f37141f5f31a6bfc05b89f55d7e4d
ALLOWED_FILE=src/ast/rewriter/seq_rewriter.cpp

# ---- 1. this must be the real upstream clone with a warm build ------------
if [ ! -f /app/src/src/ast/rewriter/seq_rewriter.cpp ] || [ ! -x /app/src/build/z3 ]; then
    echo "FAIL: /app/src is not the Z3 tree with a warm build" >&2
    failures=1
fi

# ---- 2. provenance ---------------------------------------------------------
if [ -d /app/src/.git ]; then
    head=$(cd /app/src && git rev-parse HEAD 2>/dev/null || echo "no-head")
    if [ "$head" != "$PARENT_SHA" ]; then
        echo "FAIL: HEAD is $head, expected pinned parent $PARENT_SHA" >&2
        failures=1
    fi
    porcelain=$(cd /app/src && git status --porcelain 2>/dev/null)
    untracked=$(printf '%s\n' "$porcelain" | grep -c '^??' || true)
    if [ "$untracked" -ne 0 ]; then
        echo "FAIL: untracked files present in /app/src" >&2
        printf '%s\n' "$porcelain" | grep '^??' >&2
        failures=1
    fi
    mods=$(printf '%s\n' "$porcelain" | grep -v '^??' | sed 's/^.. //' | grep -v '^$' || true)
    nmods=$(printf '%s\n' "$mods" | grep -c . || true)
    if [ "$nmods" -ne 1 ]; then
        echo "FAIL: expected exactly one modified tracked file, got $nmods" >&2
        printf '%s\n' "$porcelain" >&2
        failures=1
    else
        if [ "$mods" != "$ALLOWED_FILE" ]; then
            echo "FAIL: modified file is '$mod', expected exactly '$ALLOWED_FILE'" >&2
            failures=1
        fi
    fi
    if (cd /app/src && git diff --quiet HEAD -- "$ALLOWED_FILE"); then
        echo "FAIL: $ALLOWED_FILE is byte-identical to the pinned commit (no fix applied)" >&2
        failures=1
    fi
else
    echo "FAIL: /app/src/.git missing" >&2
    failures=1
fi

# ---- 3. deliverable: /app/summary.md --------------------------------------
if [ ! -f /app/summary.md ]; then
    echo "FAIL: deliverable /app/summary.md missing" >&2
    failures=1
else
    sz=$(wc -c < /app/summary.md 2>/dev/null || echo 0)
    if [ "$sz" -lt 100 ]; then
        echo "FAIL: /app/summary.md too short ($sz bytes)" >&2
        failures=1
    else
        echo "summary.md: acceptable ($sz bytes)"
    fi
fi

# ---- 4. rebuild the agent's tree and run the project's own tests ----------
( cd /app/src && cmake --build build --target shell > /tmp/verify_shell.log 2>&1 ) && \
    [ -x /app/src/build/z3 ] || {
    echo "FAIL: could not (re)build build/z3 from the tree" >&2
    tail -15 /tmp/verify_shell.log >&2
    failures=1
}

if [ -d /app/src ]; then
    # Plant the project's own regression test (comment-stripped fix-commit
    # bytes from /opt/golden; see environment/Dockerfile).
    cp /opt/golden/seq_rewriter.cpp /app/src/src/test/seq_rewriter.cpp \
     && ( cd /app/src && cmake --build build --target test-z3 > /tmp/verify_tz.log 2>&1 ) \
     && [ -x /app/src/build/test-z3 ] \
     || {
        echo "FAIL: planting golden test / rebuilding test-z3 failed" >&2
        tail -15 /tmp/verify_tz.log 2>/dev/null >&2
        failures=1
    }
    if [ $failures -eq 0 ]; then
        tzlog=/tmp/verify_golden.log
        if ( cd /app/src && ./build/test-z3 seq_rewriter > "$tzlog" 2>&1 ); then
            if grep -q "tst_seq_rewriter: all tests passed" "$tzlog"; then
                echo "project's own seq_rewriter module (golden planted): PASS ($(grep -c 'PASS' "$tzlog") PASS)"
            else
                echo "FAIL: test-z3 seq_rewriter exited 0 but did not report all tests passed" >&2
                tail -10 "$tzlog" >&2
                failures=1
            fi
        else
            echo "FAIL: test-z3 seq_rewriter did not pass" >&2
            tail -15 "$tzlog" >&2
            failures=1
        fi
    fi
fi

# ---- 5. hidden SMT2 cases through the agent-built binary -------------------
for case_dir in /tests/hidden/*/; do
    [ -d "$case_dir" ] || continue
    cname=$(basename "$case_dir")
    if [ ! -f "$case_dir/input.smt2" ] || [ ! -f "$case_dir/expected" ]; then
        echo "FAIL: hidden case $cname missing input.smt2 or expected" >&2
        failures=1
        continue
    fi
    verdict=$(cd /app/src && ./build/z3 "$case_dir/input.smt2" 2>/dev/null | head -1)
    expected=$(head -1 "$case_dir/expected")
    if [ -z "$verdict" ]; then
        echo "FAIL: hidden case $cname: build/z3 produced no verdict" >&2
        failures=1
    elif [ "$verdict" != "$expected" ]; then
        echo "FAIL: hidden case $cname: got '$verdict', expected '$expected'" >&2
        failures=1
    else
        echo "hidden case $cname: PASS (verdict '$verdict')"
    fi
done

if [ $failures -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0