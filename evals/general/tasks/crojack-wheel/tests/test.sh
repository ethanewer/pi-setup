#!/bin/bash
# Verifier for crojack-wheel. Checks, in order:
#  1. the declared deliverable /app/src/repro_issue.py exists,
#  2. the repro detects the bug on the pristine pre-fix tree (/opt/prefix,
#     a git-archive copy of the parent commit): running it there must exit 1,
#  3. the repro passes against the repaired tree (/app/src): exit 0,
#  4. the golden regression test extracted from the upstream fix commit
#     (/opt/golden/test_session.py, the project's own test
#     test_get_with_for_update_use, four variants) passes after being
#     overlaid onto the tree,
#  5. the project's own full test/orm/test_session.py suite still passes
#     (212 pre-existing tests + the 4 golden = 216),
#  6. every authored hidden case under /tests/hidden/*/run.py passes: each
#     exercises the same identity-map fast-path from inputs the upstream
#     test does not use (string PK, query-loaded identity entry, composite
#     PK) against the repaired tree.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

fail() {
    echo "FAIL: $*"
    failures=$((failures + 1))
}

# ---- 1. deliverable exists --------------------------------------------------
if [ ! -f /app/src/repro_issue.py ]; then
    fail "deliverable /app/src/repro_issue.py is missing"
else
    echo "deliverable /app/src/repro_issue.py: present"
fi

# ---- 2. repro must detect the bug on the pristine pre-fix tree --------------
# Run from a neutral cwd with the environment scrubbed to just PYTHONPATH and
# the minimum a real script needs, so a repro cannot cheat by inspecting
# cwd/env to decide which side of the bug it is on.
if [ -f /app/src/repro_issue.py ]; then
    rlog=/tmp/verifier_repro_pristine.log
    if ( cd /tmp && env -i HOME=/tmp PATH="$PATH" PYTHONPATH=/opt/prefix/lib \
            python3 /app/src/repro_issue.py ) > "$rlog" 2>&1; then
        fail "repro_issue.py exited 0 on the pristine pre-fix tree; a real reproduction must observe the bug there (expected nonzero exit)"
        cat "$rlog" >&2
    else
        echo "repro on pristine pre-fix tree: detects the bug (exit $?)"
        cat "$rlog" | tail -2
    fi
fi

# ---- 3. repro must pass on the repaired tree --------------------------------
if [ -f /app/src/repro_issue.py ]; then
    rlog=/tmp/verifier_repro_fixed.log
    if ( cd /tmp && env -i HOME=/tmp PATH="$PATH" PYTHONPATH=/app/src/lib \
            python3 /app/src/repro_issue.py ) > "$rlog" 2>&1; then
        echo "repro on repaired tree: OK"
        cat "$rlog" | tail -2
    else
        fail "repro_issue.py did NOT pass on the repaired tree (expected exit 0)"
        cat "$rlog" >&2
    fi
fi

# ---- 4. golden regression test from the fix commit --------------------------
glog=/tmp/verifier_golden.log
if [ -f /opt/golden/test_session.py ]; then
    if cp /opt/golden/test_session.py /app/src/test/orm/test_session.py \
        && ( cd /tmp && PYTHONPATH=/app/src/lib python3 -m pytest \
                "/app/src/test/orm/test_session.py::SessionUtilTest::test_get_with_for_update_use" \
                -q -p no:cacheprovider > "$glog" 2>&1 ) \
        && grep -q "4 passed" "$glog"; then
        echo "golden regression test: PASS (4/4)"
    else
        fail "golden regression test test_get_with_for_update_use did not pass 4/4 on the repaired tree"
        tail -20 "$glog" >&2
    fi
else
    fail "/opt/golden/test_session.py missing (image broken)"
fi

# ---- 5. the project's own full session suite still passes -------------------
slog=/tmp/verifier_suite.log
if ( cd /tmp && PYTHONPATH=/app/src/lib python3 -m pytest \
        /app/src/test/orm/test_session.py \
        -q -p no:cacheprovider > "$slog" 2>&1 ) \
    && grep -q "216 passed" "$slog"; then
    echo "project's own test/orm/test_session.py: PASS (216 passed)"
else
    fail "project's own test/orm/test_session.py did not fully pass (expected 216 passed)"
    tail -25 "$slog" >&2
fi

# ---- 6. authored hidden cases -----------------------------------------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.py"
    if [ -f "$run" ]; then
        hlog=/tmp/verifier_hidden_$(basename "$case_dir").log
        if ( cd /tmp && PYTHONPATH=/app/src/lib python3 "$run" > "$hlog" 2>&1 ); then
            echo "hidden case $(basename "$case_dir"): PASS"
        else
            fail "hidden case $(basename "$case_dir") failed on the repaired tree"
            tail -8 "$hlog" >&2
        fi
    fi
done

# ---- binary reward ----------------------------------------------------------
if [ "$failures" -eq 0 ]; then
    echo "VERIFIER: all checks passed"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: $failures check(s) failed" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0