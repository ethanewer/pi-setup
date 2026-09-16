#!/bin/bash
# Verifier for conduit-anchor: proves the agent's fix in the real
# pytest-dev/pytest tree at /app/src by
#   1. asserting provenance (HEAD still the pinned parent commit; every
#      tracked file except the single approx-machinery source file
#      src/_pytest/python_api.py is byte-identical to the parent commit's
#      blobs; no stray untracked non-ignored files),
#   2. requiring /app/summary.md,
#   3. asserting the GRADED python code is the clone's own (the editable
#      install resolves _pytest.python_api from /app/src/src, not from a
#      site-packages shim),
#   4. overlaying the project's OWN regression tests for this bug (the
#      testing/python/approx.py state that landed WITH the fix, extracted
#      from the fix commit at image build time into /opt/golden) over the
#      in-tree test file, then running the approx suite and the whole
#      testing/python/ suite with the project's own runner,
#   5. running the three authored hidden generalization cases,
#   6. demanding that every required test actually RAN and PASSED (a
#      neutralised run or a sabotaged selection would leave no "::<name>
#      PASSED" line even if pytest exited 0).
# Reward is binary and written on every exit path (the trap covers crashes).
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

PARENT=fbab7c5dfe63a22f545207e8dc163ed61ad51d98
cd /app/src || fail "/app/src is missing"

# 0a) Purge interpreter caches the agent may have planted, then reject any
#     startup wrapper. The editable install puts /app/src ('' from
#     sys.path[0]) and /app/src/src on sys.path BEFORE sitecustomize is
#     imported, and both *.pyc and __pycache__/ are git-ignored, so without
#     this an agent can patch the approx machinery at interpreter startup
#     from bytecode while every tracked source blob stays byte-identical.
#     Demonstrated during review (2026-09-12): an ignored
#     sitecustomize.pyc in /app/src/src earned reward 1 with an empty
#     `git status --porcelain`. We delete every bytecode cache under the
#     clone, then fail on any sitecustomize/usercustomize file under /app
#     or on any sitecustomize that resolves into /app at import time.
find /app/src -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null
find /app/src \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null
wrappers=$(find /app /app/src \( -name 'sitecustomize.*' -o -name 'usercustomize.*' \) 2>/dev/null | head -5)
[ -z "$wrappers" ] || fail "startup wrapper planted under /app: $wrappers"
sc=$(python3 -c "import sitecustomize; print(sitecustomize.__file__)" 2>/dev/null || true)
case "$sc" in
    /app/*) fail "sitecustomize import resolves into the app: $sc" ;;
esac

# 0) The graded python code must be the clone's own modules (editable install
#    of /app/src), not a site-packages shadow the agent could have planted.
IMPORTED=$(python3 -c "import _pytest.python_api as m; print(m.__file__)" 2>/dev/null || true)
case "$IMPORTED" in
    /app/src/src/*) : ;;
    *) fail "imported _pytest.python_api is not the /app/src clone: ${IMPORTED:-unimportable}" ;;
esac

# 1) The tree must still be at the pinned parent commit (no commits added,
#    and nothing can hide work from the blob-level scope check below).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) Scope: every change must live in exactly the one source file the bug is
#    in (in src/_pytest/python_api.py, discovered by the agent, not named
#    here). This is a CONTENT check, not a git-status check: we hash the
#    actual bytes of every tracked file on disk against the pinned commit's
#    own blob (so assume-unchanged/skip-worktree tricks cannot hide a dirty
#    file) and refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/_pytest/python_api.py) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"
                ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"
    ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 2b) The bug's source file must actually have been changed. With the
#     startup-wrapper check above, a python_api.py that is byte-identical to
#     the pinned parent commit means no fix was made in the tree at all.
[ "$(git hash-object -- src/_pytest/python_api.py)" != "$(git rev-parse "$PARENT:src/_pytest/python_api.py")" ] \
    || fail "src/_pytest/python_api.py is byte-identical to the pinned parent commit: no fix in the tree"

# 3) Deliverable: the agent's own change summary must exist (this task IS
#    about changing the tree, so empty writing is not a summary).
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -qi "timedelta" /app/summary.md || fail "/app/summary.md does not describe the timedelta approx change"

# 4) Plant the upstream regression test file for this bug (golden bytes,
#    extracted from the fix commit at image build time; never part of this
#    task tree) over the in-tree copy, which still encodes the old behaviour.
[ -s /opt/golden/approx.py ] || fail "/opt/golden/approx.py is missing"
cp /opt/golden/approx.py testing/python/approx.py || fail "cannot overlay golden approx.py"
grep -q "test_timedelta_rel_must_be_number" testing/python/approx.py \
    || fail "golden overlay did not take (test_timedelta_rel_must_be_number absent)"

# 5) The project's OWN runner on the approx suite: the full golden file must
#    pass and each of the seven regression tests for this bug must actually
#    have run and passed.
if ! python3 -m pytest testing/python/approx.py -v -p no:cacheprovider > /logs/verifier/golden.log 2>&1; then
    tail -60 /logs/verifier/golden.log >&2
    fail "golden testing/python/approx.py suite failed (see /logs/verifier/golden.log)"
fi
for t in \
    test_timedelta_rel_must_be_number \
    test_timedelta_rel_must_be_non_negative \
    test_timedelta_rel_must_not_be_nan \
    test_timedelta_rel_with_abs \
    test_timedelta_rel_scales_with_expected \
    test_timedelta_in_sequence \
    test_timedelta_in_mapping; do
    if ! grep -q "::${t} PASSED" /logs/verifier/golden.log; then
        fail "required regression test ${t} did not run and pass (see /logs/verifier/golden.log)"
    fi
done

# 6) The project's own existing suite region the change touches must stay
#    green: the whole testing/python/ tree with the golden approx overlaid.
if ! python3 -m pytest testing/python/ -q -p no:cacheprovider > /logs/verifier/suite.log 2>&1; then
    tail -60 /logs/verifier/suite.log >&2
    fail "testing/python/ suite failed (see /logs/verifier/suite.log)"
fi

# 7) The authored hidden generalization cases (inputs the upstream regression
#    tests do not use: microsecond/negative/large-magnitude tolerances,
#    validation of negative/NaN tolerances, tuple and multi-entry-mapping
#    routing). Each file must pass.
HIDDEN=/tests/hidden
if [ ! -d "$HIDDEN" ]; then
    fail "no hidden cases present"
fi
cases=0
for case in "$HIDDEN"/*; do
    [ -d "$case" ] || continue
    for tf in "$case"/*.py; do
        [ -f "$tf" ] || continue
        cases=$((cases + 1))
        if ! python3 -m pytest "$tf" -q -p no:cacheprovider > /logs/verifier/hidden.log 2>&1; then
            tail -60 /logs/verifier/hidden.log >&2
            fail "hidden case $tf FAILED (see /logs/verifier/hidden.log)"
        fi
    done
done
[ "$cases" -ge 3 ] || fail "expected at least 3 hidden case files, found $cases"

# 8) Belt: the agent's fix must be live in a fresh interpreter.
if ! python3 /app/repro_symptom.py > /logs/verifier/repro.log 2>&1; then
    tail -20 /logs/verifier/repro.log >&2
    fail "repro_symptom.py did not pass (see /logs/verifier/repro.log)"
fi

echo 1 > /logs/verifier/reward.txt
exit 0