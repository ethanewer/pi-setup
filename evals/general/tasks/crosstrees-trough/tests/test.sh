#!/bin/bash
# Verifier for crosstrees-trough (real upstream tmux, real verified defect).
#
# Design: the tree is rebuilt in two states and every behavioural check runs in
# BOTH of them, so no wrapper, hardcoded expectation, skipped test or edited
# regression script can earn the reward without a genuine source fix in the
# shipped /app/src tree:
#   - PRistine state  = the pinned buggy commit recreated via git; the agent's
#     committed AND uncommitted work is preserved on a branch/stash first.
#     Here the deliverable repro, the upstream regression test, and the three
#     hidden cases must all FAIL with the expected symptom.
#   - REpaired state  = the tree exactly as the agent left it (restored), with
#     the fix in place. Everything must PASS: repro, golden test, hidden
#     cases, three more of the project's own regress/ scripts, and a static
#     root-cause check that the combine visibility query includes the pane
#     x offset (catches render-masking hacks that leave the bug in place).
# Reward is binary (1/0) and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

PIN_SHA=936bb6e7cdff4fc7700a4f36a6b828b87d9f8241
BIN=/app/src/tmux
REPRO=/app/repro.sh
GOLDEN=/opt/golden/tty-draw-line.sh
GOLDEN_SHA256=1d5231897c32f83c96c861edfd43c4d1a40c31901f854be68ce2c659eebcc92b
# (case-dir, expected sha256) for the authored hidden cases
HIDDEN="airplane_offset2:f4e947cdf2fad03cd6c39507955aaf8fe1a106bc59cdac757e10bc89f4487857
heart_offset30:dd5c8149203a9dfbf86ca7e05e63a78140c0abf8e696d4b6a75abb574a1300ae
pencil_grid23:ec852bb898f958e4ad996fe39d073853c1304aa0e4e4e7c03132b998c802a9b0"
# extra upstream regress scripts run on the repaired tree
SUITE="combine-test.sh screen-redraw-fill-character.sh screen-redraw-cache.sh"

fail() { echo "FAIL: $*" >&2; failures=1; }
ok() { echo "ok: $*"; }

# ---------------- 0. environment integrity and deliverable -------------------
if [ ! -d /app/src/.git ]; then
    fail "/app/src is not a git checkout"
fi
if [ ! -x "$BIN" ]; then
    fail "no tmux binary at $BIN"
fi
if [ ! -f "$GOLDEN" ]; then
    fail "golden test $GOLDEN missing"
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
    fail "golden test $GOLDEN was modified (sha256 mismatch)"
fi
if [ ! -f "$REPRO" ]; then
    fail "deliverable /app/repro.sh missing"
elif [ ! -x "$REPRO" ]; then
    fail "deliverable /app/repro.sh exists but is not executable"
elif [ ! -s "$REPRO" ]; then
    fail "deliverable /app/repro.sh is empty"
fi

# ---------------- helpers ----------------------------------------------------
rebuild() {
    # shellcheck disable=SC2010
    ( cd /app/src && make clean >/dev/null 2>&1; make -j1 >/tmp/vbuild.log 2>&1 )
}

save_agent_state() {
    cd /app/src || return 1
    AGENT_HEAD=$(git rev-parse HEAD) && echo "$AGENT_HEAD" >/tmp/agent_head.txt || return 1
    git branch -f verifier-agent-state HEAD 2>/dev/null || return 1
    git add -A 2>/dev/null || return 1
    git stash push -u -m verifier-save >/dev/null 2>&1 || true
    git reset -q --hard "$PIN_SHA" || return 1
    git clean -fdq || return 1
    [ "$(git rev-parse HEAD)" = "$PIN_SHA" ] || return 1
    [ -z "$(git status --porcelain)" ] || return 1
    return 0
}

restore_agent_state() {
    cd /app/src || return 1
    git reset -q --hard verifier-agent-state || return 1
    git stash pop >/dev/null 2>&1 || true
    saved=$(cat /tmp/agent_head.txt 2>/dev/null)
    [ -n "$saved" ] && [ "$(git rev-parse HEAD)" = "$saved" ] || return 1
    return 0
}

run_hidden() {  # $1 = case-id (must equal a line prefix in $HIDDEN)
    case_id=$1
    want=$(printf '%s\n' "$HIDDEN" | awk -F: -v c="$case_id" '$1 == c {print $2; exit}')
    run=/tests/hidden/$case_id/run.sh
    if [ -z "$want" ]; then
        fail "hidden case $case_id not registered in verifier"
        return 1
    fi
    if [ ! -f "$run" ] || [ "$(sha256sum "$run" | awk '{print $1}')" != "$want" ]; then
        fail "hidden case $case_id script missing or modified (sha256 mismatch)"
        return 1
    fi
    timeout 120 sh "$run" "$BIN" >/tmp/vhidden.log 2>&1
    r=$?
    if [ $r -ne 0 ]; then
        tail -3 /tmp/vhidden.log >&2
        return $r
    fi
    return 0
}

expect_fail() {  # $1 = label, $2.. = command
    label=$1; shift
    timeout 300 "$@" >/tmp/vexpect.log 2>&1
    r=$?
    if [ $r -eq 0 ]; then
        fail "$label unexpectedly PASSED (exit 0) - defect not present?"
        return 1
    fi
    ok "$label fails as required (exit $r)"
    return 0
}

expect_pass() {  # $1 = label, $2.. = command
    label=$1; shift
    timeout 300 "$@" >/tmp/vexpect.log 2>&1
    r=$?
    if [ $r -ne 0 ]; then
        fail "$label FAILED (exit $r)"
        tail -8 /tmp/vexpect.log >&2
        return 1
    fi
    ok "$label passes"
    return 0
}

# ---------------- phase 1: pristine (defect-present) tree --------------------
if [ $failures -eq 0 ]; then
    if save_agent_state; then
        ok "preserved agent state (HEAD $(cut -c1-8 /tmp/agent_head.txt)); recreated pinned tree"
    else
        fail "could not recreate the pristine pinned tree from git"
    fi
fi
if [ $failures -eq 0 ]; then
    if rebuild; then
        ok "pristine rebuild succeeded"
    else
        fail "pristine rebuild failed:"
        tail -8 /tmp/vbuild.log >&2
    fi
fi
if [ $failures -eq 0 ]; then
    expect_fail "agent repro on pristine (defect-present) build" sh "$REPRO" \
        || true
    # golden must fail, and fail with the expected dropped-character message
    TEST_TMUX="$BIN" timeout 180 sh "$GOLDEN" >/tmp/vgolden.log 2>&1
    grc=$?
    if [ $grc -eq 0 ]; then
        fail "upstream golden test passed on pristine build - defect not reproduced"
    elif grep -qF "expected" /tmp/vgolden.log && grep -qF "got" /tmp/vgolden.log; then
        ok "upstream golden test fails on pristine build (exit $grc) with the expected message"
    else
        fail "golden test failed (exit $grc) but not with the expected message"
        tail -5 /tmp/vgolden.log >&2
    fi
    for hid in airplane_offset2 heart_offset30 pencil_grid23; do
        if run_hidden "$hid"; then
            fail "hidden case $hid passed on pristine (defect-present) build"
        else
            ok "hidden case $hid fails on pristine build (calibrated)"
        fi
    done
fi

# ---------------- phase 2: repaired (agent) tree -----------------------------
if [ $failures -eq 0 ]; then
    if restore_agent_state; then
        ok "restored agent state"
    else
        fail "could not restore the agent's tree state"
    fi
fi
if [ $failures -eq 0 ]; then
    if rebuild; then
        ok "repaired rebuild succeeded"
    else
        fail "repaired rebuild failed:"
        tail -8 /tmp/vbuild.log >&2
    fi
fi
# Root-cause check on the repaired tree: the screen_write_combine visibility
# query must use WINDOW coordinates (pane x offset included), i.e. the
# upstream 696a16cc fix. This is what separates a genuine fix from masking
# hacks that leave the pane-relative query in place (e.g. forcing vis>=n so
# nothing is ever deemed obscured - such a hack passes every render-only
# check because a plain non-overlapping geometry never actually obscures a
# cell, so the behavioral tests cannot tell it apart from the real fix).
if [ $failures -eq 0 ]; then
    sw=/app/src/screen-write.c
    if [ ! -f "$sw" ]; then
        fail "screen-write.c missing from the repaired tree"
    elif grep -nE 'window_visible_ranges\(wp, cx - n, (cy|yoff)' "$sw" >/dev/null; then
        fail "repaired tree still contains the pane-relative visibility query (root cause not fixed)"
    elif grep -nE 'window_visible_ranges\(wp,[[:space:]]*[^,]*xoff[^,]*,[[:space:]]*(cy \+ yoff|yoff \+ cy)' "$sw" >/dev/null \
         || grep -nE 'window_visible_ranges\(wp,[[:space:]]*[^,]*wp->xoff[^,]*,[[:space:]]*(cy \+ yoff|yoff \+ cy)' "$sw" >/dev/null; then
        ok "combine visibility query now uses window coordinates (xoff included)"
    else
        fail "combine visibility query in screen-write.c does not include the pane x offset"
    fi
fi
if [ $failures -eq 0 ]; then
    expect_pass "agent repro on repaired build" sh "$REPRO" || true
    expect_pass "upstream golden test on repaired build" env TEST_TMUX="$BIN" sh "$GOLDEN" || true
    for hid in airplane_offset2 heart_offset30 pencil_grid23; do
        if run_hidden "$hid"; then
            ok "hidden case $hid passes on repaired build"
        else
            fail "hidden case $hid failed on repaired build"
        fi
    done
    for s in $SUITE; do
        if (cd /app/src/regress && TEST_TMUX=$PWD/../tmux timeout 300 sh "./$s" >/tmp/vsuite.log 2>&1); then
            ok "upstream regress $s passes on repaired build"
        else
            fail "upstream regress $s failed on repaired build"
            tail -6 /tmp/vsuite.log >&2
        fi
    done
fi

# ---------------- reward -------------------------------------------------------
if [ $failures -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0