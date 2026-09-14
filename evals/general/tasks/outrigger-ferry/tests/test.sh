#!/bin/bash
# Verifier for outrigger-ferry: proves the agent's fix in the real
# python-poetry/poetry tree at /app/src (upstream issue #10804) by
#  0. asserting the verifier's own trust anchors (sha256 of the golden
#     regression test at /opt/golden/test_executor.py, of the pristine
#     pre-fix bug-file at /opt/pre-fix-poetry/poetry/installation/
#     executor.py, and of the venv python and git binaries);
#  1. asserting provenance (HEAD still the pinned parent commit; the
#     upstream fix commit is not reachable from this clone; exactly one
#     commit object; no assume-unchanged/skip-worktree index flags; the
#     only tracked file that may differ from the parent blobs is
#     src/poetry/installation/executor.py and it must actually differ; no
#     untracked non-ignored files);
#  2. requiring the declared deliverables /app/repro.py and
#     /app/summary.md;
#  3. running the agent's own reproduction against the repaired tree (must
#     exit 0 and print the whole-string flag) and against the pristine
#     pre-fix package bake at /opt/pre-fix-poetry under PYTHONPATH (must
#     fail with the per-character garble - proves the symptom is real and
#     the reproduction targets it);
#  4. running the previously-green suite slice (~940 tests: chooser,
#     chooser_errors, installer, wheel_installer, packages, and executor
#     minus the three environment-broken embedded-wheel tests) to prove
#     the fix broke nothing else;
#  5. planting the project's own regression test for this bug (the fix
#     commit's tests/installation/test_executor.py, extracted at image
#     build time into /opt/golden and sha256-pinned) and requiring
#     test_build_backend_error_includes_config_settings_in_pip_command to
#     pass, and requiring the same golden test to FAIL against the
#     pre-fix copy;
#  6. running three authored hidden cases that reach the same error-path
#     pip-command construction from inputs the upstream regression test
#     does not use (multi-string settings incl. a value with a space; an
#     empty-string value; a punctuation/digit-heavy value), each must pass
#     on the repaired tree and fail on the pre-fix copy.
#
# Reward is binary and is rewritten unconditionally by the EXIT trap from
# the $reward variable, so no exit path can leave a forged or stale value.
trap 'printf "%s\n" "${reward:-0}" > /logs/verifier/reward.txt' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
reward=1
LOG=/logs/verifier/verifier.log
: > "$LOG"

SRC=/app/src
PY=/opt/poetry-venv/bin/python3
PYTEST=/opt/poetry-venv/bin/pytest
GIT=/usr/bin/git
PARENT_SHA=378c693f0e63da2c4669b2158c31ecadfa619587
FIX_SHA=35eb5025dc7374db74ef26ce32a0e70f54d2e3b6

# sha256 as recorded from the built outrigger-ferry image at authoring time.
INTEGRITY_SHA_GOLDEN=a70e8b71cde7776681828c7c2d72a1cb7594e322ff17e971169c50dd48deae35
INTEGRITY_SHA_PREFIX_EXECUTOR=290edb2cb8454bfdd7e8b87a04ad5521ae6a19c2e2b6302d7c8a1cc8aa74b4ed
INTEGRITY_SHA_PYTHON=0e6475dfda68a9b2d93501449fc47593ca169010e8f4881577b97463fd0c1263
INTEGRITY_SHA_GIT=356db14e102d68a1a37d8a1ac577dfd678d45d46e92f468bef8b7154e7bfdc60

fail() {  # fail LABEL MESSAGE
    echo "FAIL: $1: $2" | tee -a "$LOG"
    reward=0
}

check_sha () {  # check_sha LABEL EXPECTED FILE
    local label="$1" expected="$2" file="$3"
    if [ ! -f "$file" ]; then
        fail "integrity/$label" "$file is missing (toolchain or harness was replaced or deleted)"
        return 1
    fi
    local actual
    actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        fail "integrity/$label" "$file does not match the recorded bytes (was it replaced?)"
        return 1
    fi
    echo "ok: integrity/$label matches the recorded sha256"
    return 0
}

# ---------- 0. integrity anchors --------------------------------------------
echo "== toolchain and harness integrity =="
check_sha golden  "$INTEGRITY_SHA_GOLDEN"        "/opt/golden/test_executor.py"           || true
check_sha prefix  "$INTEGRITY_SHA_PREFIX_EXECUTOR" "/opt/pre-fix-poetry/poetry/installation/executor.py" || true
check_sha python  "$INTEGRITY_SHA_PYTHON"        "$PY"                                    || true
check_sha git     "$INTEGRITY_SHA_GIT"           "$GIT"                                   || true

# ---------- 1. provenance ------------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
    fail "provenance" "/app/src is not a git clone"
elif [ "$("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
    fail "provenance" "HEAD is $("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null), expected pinned $PARENT_SHA"
else
    echo "ok: HEAD is $PARENT_SHA"
fi

if "$GIT" -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "provenance" "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
    echo "ok: fix commit not present in the working clone"
fi

ncommits=$("$GIT" -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
    fail "provenance" "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
    echo "ok: exactly one commit object reachable in the working clone"
fi

flagged=$("$GIT" -C "$SRC" ls-files -v 2>/dev/null | awk '
    NF >= 2 && $1 ~ /^[hS]/ { print }
')
if [ -n "$flagged" ]; then
    fail "provenance" "tracked files carry assume-unchanged/skip-worktree index flags (changes would be hidden from status)"
    echo "$flagged" | sed 's/^/    | /' | tee -a "$LOG"
else
    echo "ok: no assume-unchanged / skip-worktree flags in the index"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        " M src/poetry/installation/executor.py")
            saw_mod=1
            ;;
        " M "*)
            echo "tracked file outside the bug's source file was modified: $line" >> "$LOG"
            bad_tree=1
            ;;
        " D "*) echo "a tracked file was deleted: $line" >> "$LOG"; bad_tree=1 ;;
        "?? "*)
            echo "untracked non-ignored file present: $line" >> "$LOG"; bad_tree=1 ;;
        *) echo "unexpected working-tree change: $line" >> "$LOG"; bad_tree=1 ;;
    esac
done <<< "$("$GIT" -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then
    fail "provenance" "disallowed working-tree changes (see $LOG)"
else
    echo "ok: no disallowed working-tree changes"
fi
if [ "$saw_mod" = 0 ]; then
    fail "provenance" "src/poetry/installation/executor.py is byte-identical to the parent commit - the shipped tree was never repaired"
else
    echo "ok: the bug's source file is modified in the tree"
fi

# ---------- 2. deliverables -----------------------------------------------------
echo "== deliverables =="
[ -s /app/repro.py ]    || fail "deliverables" "/app/repro.py is missing or empty"
[ -s /app/summary.md ]  || fail "deliverables" "/app/summary.md is missing or empty"

# ---------- 3. the agent's reproduction, both directions -------------------------
echo "== agent reproduction =="
if ! "$PY" /app/repro.py > /tmp/ver_repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/ver_repro_fixed.out >> "$LOG"
    fail "repro" "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if ! grep -q -- "--config-settings='CC=gcc'" /tmp/ver_repro_fixed.out; then
    fail "repro" "agent repro did not print the whole-string flag on the repaired tree (see $LOG)"
else
    echo "ok: repro on the repaired tree prints --config-settings='CC=gcc'"
fi

PYTHONPATH=/opt/pre-fix-poetry "$PY" /app/repro.py > /tmp/ver_repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX copy (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/ver_repro_prefix.out >> "$LOG"
    fail "repro" "agent repro did not fail on the pre-fix copy (see $LOG)"
fi
if ! grep -q -- "--config-settings='CC=g'" /tmp/ver_repro_prefix.out; then
    fail "repro" "pre-fix failure was not the per-character garbling symptom (see $LOG)"
else
    echo "ok: repro on the pre-fix copy fails with the per-character garble"
fi

# ---------- 4. previously-existing suite slice ------------------------------------
echo "== the project's own existing tests (regression slice) =="
if ( cd "$SRC" && "$PYTEST" \
        tests/installation/test_chooser.py \
        tests/installation/test_chooser_errors.py \
        tests/installation/test_installer.py \
        tests/installation/test_wheel_installer.py \
        tests/packages \
        -q --no-header -p no:randomly -o addopts="" > "$LOG.suite1" 2>&1 ); then
    if grep -q "617 passed" "$LOG.suite1"; then
        echo "ok: suite slice 1 green (chooser + installer + wheel_installer + packages)"
    else
        tail -20 "$LOG.suite1" >&2
        fail "suite" "slice 1 did not report the expected passed count (see $LOG.suite1)"
    fi
else
    tail -30 "$LOG.suite1" >&2
    fail "suite" "slice 1 not green on the repaired tree (see $LOG.suite1)"
fi

if ( cd "$SRC" && "$PYTEST" tests/installation/test_executor.py \
        --deselect "tests/installation/test_executor.py::test_execute_executes_a_batch_of_operations" \
        --deselect "tests/installation/test_executor.py::test_execute_prints_warning_for_yanked_package" \
        -q --no-header -p no:randomly -o addopts="" > "$LOG.suite2" 2>&1 ); then
    if grep -q "74 passed" "$LOG.suite2"; then
        echo "ok: suite slice 2 green (executor minus environment-broken tests)"
    else
        tail -20 "$LOG.suite2" >&2
        fail "suite" "executor slice did not report 74 passed (see $LOG.suite2)"
    fi
else
    tail -30 "$LOG.suite2" >&2
    fail "suite" "executor slice not green on the repaired tree (see $LOG.suite2)"
fi

# ---------- 5. golden: the upstream regression test -------------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s /opt/golden/test_executor.py ]; then
    fail "golden" "golden file missing from the image"
else
    check_sha golden "$INTEGRITY_SHA_GOLDEN" "/opt/golden/test_executor.py" || true
    cp /opt/golden/test_executor.py "$SRC/tests/installation/test_executor.py"
    if [ "$(sha256sum "$SRC/tests/installation/test_executor.py" | awk '{print $1}')" != "$INTEGRITY_SHA_GOLDEN" ]; then
        fail "golden" "planted test_executor.py does not match the pinned golden bytes"
    elif ! ( cd "$SRC" && "$PYTEST" tests/installation/test_executor.py \
            -k test_build_backend_error_includes_config_settings_in_pip_command \
            -q --no-header -p no:randomly -o addopts="" > "$LOG.golden" 2>&1 ); then
        tail -25 "$LOG.golden" >&2
        fail "golden" "golden regression test did not pass on the repaired tree (see $LOG.golden)"
    else
        grep -q "1 passed" "$LOG.golden" || \
            fail "golden" "golden test did not report 1 passed (see $LOG.golden)"
        echo "ok: golden regression test passes on the repaired tree"
    fi

    # the same golden test must FAIL against the pristine pre-fix copy
    if ( cd "$SRC" && PYTHONPATH=/opt/pre-fix-poetry "$PYTEST" \
            tests/installation/test_executor.py \
            -k test_build_backend_error_includes_config_settings_in_pip_command \
            -q --no-header -p no:randomly -o addopts="" > "$LOG.goldenprefix" 2>&1 ); then
        fail "golden" "golden regression test PASSED against the pre-fix copy (must fail; copy was tampered with?)"
    else
        if grep -q "1 failed" "$LOG.goldenprefix"; then
            echo "ok: golden regression test fails on the pre-fix copy"
        else
            tail -15 "$LOG.goldenprefix" >&2
            fail "golden" "pre-fix golden run failed for an unexpected reason (see $LOG.goldenprefix)"
        fi
    fi
    "$GIT" -C "$SRC" checkout -q -- tests/installation/test_executor.py
fi

# ---------- 6. hidden cases ---------------------------------------------------------
echo "== hidden cases =="
HC_DIR="$SRC/tests/installation"
cp /tests/hidden/case-multi-string/test_hidden_multi_string.py     "$HC_DIR/" || fail "hidden" "cannot read hidden case case-multi-string"
cp /tests/hidden/case-empty-string/test_hidden_empty_string.py     "$HC_DIR/" || fail "hidden" "cannot read hidden case case-empty-string"
cp /tests/hidden/case-punctuation/test_hidden_punctuation.py      "$HC_DIR/" || fail "hidden" "cannot read hidden case case-punctuation"

HC_FILES="tests/installation/test_hidden_multi_string.py tests/installation/test_hidden_empty_string.py tests/installation/test_hidden_punctuation.py"
if ( cd "$SRC" && "$PYTEST" $HC_FILES -q --no-header -p no:randomly -o addopts="" > "$LOG.hidden" 2>&1 ); then
    if grep -q "3 passed" "$LOG.hidden"; then
        echo "ok: all three hidden cases pass on the repaired tree"
    else
        tail -20 "$LOG.hidden" >&2
        fail "hidden" "hidden cases did not report 3 passed (see $LOG.hidden)"
    fi
else
    tail -30 "$LOG.hidden" >&2
    fail "hidden" "hidden cases not green on the repaired tree (see $LOG.hidden)"
fi

# every hidden case must ALSO fail against the pristine pre-fix copy (they target
# the fixed behaviour, so a pre-fix tree cannot pass them; this proves the cases
# are not vacuous)
for hc in test_hidden_multi_string test_hidden_empty_string test_hidden_punctuation; do
    if ( cd "$SRC" && PYTHONPATH=/opt/pre-fix-poetry "$PYTEST" \
            "tests/installation/$hc.py" -q --no-header -p no:randomly \
            -o addopts="" > "$LOG.hp" 2>&1 ); then
        fail "hidden" "$hc PASSED against the pre-fix copy (must fail; copy tampered with?)"
    else
        echo "ok: hidden case $hc fails on the pre-fix copy"
    fi
done

rm -f "$HC_DIR/test_hidden_multi_string.py" "$HC_DIR/test_hidden_empty_string.py" "$HC_DIR/test_hidden_punctuation.py"

# ---------- summary -------------------------------------------------------------
if [ "$reward" = 1 ]; then
    echo "PASS: provenance, fix-unreachable, deliverables, repro both directions, upstream regression test, existing suite, hidden cases"
else
    echo "FAILURES recorded (see $LOG and stdout above); reward=0"
fi
echo "REWARD=$reward"
exit 0