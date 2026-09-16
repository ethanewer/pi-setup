#!/bin/bash
# pennant-caboose verifier.
#
# Grades a repaired redis tree on five axes:
#  (0) deliverables: /app/reproduce.sh exists and is executable, the tree's
#      built binaries are present;
#  (1) provenance: the clone is still the pinned parent commit, the upstream
#      fix commit is not reachable from it, the ONLY tracked change allowed
#      is src/t_stream.c, no stray untracked files were added, and the fix
#      is actually implemented in the source;
#  (2) the agent's OWN reproduction is honest and works: the verifier builds
#      a pristine pre-fix server by checking the parent's src/t_stream.c out
#      of the single-commit clone, rebuilding incrementally, then restoring
#      the agent's file and rebuilding again; the agent's /app/reproduce.sh
#      run against the pristine server must print VERDICT: BUGGY and run
#      against the agent's rebuilt server must print VERDICT: FIXED;
#  (3) the project's own regression test for the bug (the test 'XSETID
#      ENTRIESADDED clamps group entries_read and keeps the RDB loadable'
#      from the fix commit's tests/unit/type/stream-cgroups.tcl, extracted
#      into /opt/golden and never present in the agent's tree) must pass
#      against the rebuilt binary;
#  (4) authored hidden cases that drive the same code path from inputs the
#      upstream test does not use must pass, run through the project's
#      runtest;
#  (5) the project's own pre-existing stream consumer-group suite stays
#      green, including the two 'cap the value' tests that pin the same
#      entries_read <= entries_added rule the fix must not disturb.
#
# Writes 1/0 to /logs/verifier/reward.txt. The EXIT trap guarantees that a
# verifier that dies before writing still yields 0.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u

# Deterministic toolchain. The trial user (uid 1000) can write /app and
# $HOME but not /usr/bin, so pinning PATH here means `runtest`'s `which
# tclsh` and the make/git invocations below can never resolve to a fake
# tool the agent planted elsewhere.
export PATH=/usr/bin:/bin

mkdir -p /logs/verifier /tmp/pc

SRC=/app/src
PARENT_SHA=8f365337d48c8a264bc9f3381c7b8cc12ffb51d2
FIX_SHA=4f20cb48934463db5970bd476461b2d57af3f38d
GOLDEN_NAME="XSETID ENTRIESADDED clamps group entries_read and keeps the RDB loadable"
GOLDEN_SHA=47cfd4c5d0426f13aee50b793856fed46bbbb78e47b6d91c01d70a07c773bf29
HIDDEN_BASE="/tests/hidden"
HIDDEN_SHA="case-lower-to-zero:d660ab53fae961ebe87bf1d1b7aabc30890a2a6d146faea506c346e3b1e4988f\ncase-never-read:7db2585570b103a035d6191eb44321dc0ae4f84e98cf477034f3b79423cf8746\ncase-keep-untouched:d2461a9a2ce993a0f6347f6756c23172f9fee312e9b7814d432de822cc32f0e3"
FAILS=0

say_fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

verdict_of() {
    # prints the LAST line of stdin that is exactly VERDICT: BUGGY / VERDICT: FIXED
    grep -E '^VERDICT: (BUGGY|FIXED)$' | tail -n 1 || true
}

# ------------------------- 0. deliverables present --------------------------
[ -f "$SRC/src/t_stream.c" ] || say_fail "source tree missing src/t_stream.c"
[ -x "$SRC/src/redis-server" ] || say_fail "redis-server missing or not executable"
[ -x "$SRC/src/redis-cli" ] || say_fail "redis-cli missing or not executable"
if [ ! -x /app/reproduce.sh ]; then
    say_fail "deliverable /app/reproduce.sh missing or not executable"
fi

# ---------------------------- 1. provenance first ---------------------------
# Run before we touch the tree, so the snapshot we compare against is the
# agent's own work, not our temporary copies.
head_sha=$(git -C "$SRC" rev-parse --verify HEAD^{commit} 2>/dev/null || true)
case "$head_sha" in
    "$PARENT_SHA"*) ;;
    *) say_fail "clone HEAD is not the pinned parent commit (got '$head_sha')" ;;
esac

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    say_fail "the upstream fix commit is reachable from the clone"
fi

git -C "$SRC" status --porcelain > /tmp/pc/status_pre.txt 2>&1 || say_fail "git status failed in $SRC"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/pc/status_pre.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/t_stream.c' || true)
    if [ -n "$odd" ]; then
        say_fail "unexpected tracked changes: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/pc/status_pre.txt)
if [ -n "$untracked" ]; then
    say_fail "unexpected untracked files in tree: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

if [ -z "$(git -C "$SRC" diff -- src/t_stream.c 2>/dev/null || true)" ]; then
    say_fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi

# ---- 1b. blob-level provenance (immune to assume-unchanged/skip-worktree) ---
# `git status` obeys the assume-unchanged bit: an agent could tamper with a
# tracked harness file (e.g. tests/support/test.tcl, where assert_equal
# lives, or tests/test_helper.tcl) and hide it from status, turning every
# runtest assertion into a no-op while the real bug stays in the C code.
# Compare every tracked file's on-disk content against its index blob
# directly: only src/t_stream.c may differ (that IS the fix).
pc_audit() {
    local bad=0 label="$1"
    if ! git -C "$SRC" ls-files -v | awk 'substr($0,1,1) != "H" {print "  " $0}' > /tmp/pc/flags_$label.txt 2>&1; then
        echo "FAIL [provenance/$label] git ls-files -v failed"; return 1
    fi
    if [ -s /tmp/pc/flags_$label.txt ]; then
        echo "FAIL [provenance/$label] assume-unchanged/skip-worktree flags set on tracked files:"
        sed 's/^/    /' /tmp/pc/flags_$label.txt
        return 1
    fi
    while read -r mode blob stage path; do
        [ "$path" = "src/t_stream.c" ] && continue
        actual=$(git -C "$SRC" hash-object -- "$path" 2>/dev/null || true)
        if [ "$actual" != "$blob" ]; then
            echo "  blob mismatch: $path (index $blob vs disk ${actual:-<missing>})" >> /tmp/pc/blobs_$label.txt
            bad=1
        fi
    done < <(git -C "$SRC" ls-files -s)
    if [ "$bad" = 1 ]; then
        echo "FAIL [provenance/$label] tracked file(s) differ from the pinned commit (hidden from status?):"
        cat /tmp/pc/blobs_$label.txt | sed 's/^/    /'
        return 1
    fi
    return 0
}
if ! pc_audit pre; then
    say_fail "provenance blob audit (pre) found tampering"
fi

# ------------------- 2. stop stray servers left by the agent ----------------
pkill -f '/app/src/src/redis-server' 2>/dev/null || true
pkill -f 'redis-server.*--port' 2>/dev/null || true
sleep 0.5

# ------------- 3. rebuild so the binary reflects the agent's tree -----------
if ! ( cd "$SRC" && make -j1 > /tmp/pc/make_agent.log 2>&1 ); then
    say_fail "incremental make failed (tree does not build):"
    tail -n 15 /tmp/pc/make_agent.log >&2
fi
[ -x "$SRC/src/redis-server" ] || say_fail "redis-server not produced by make"

# ----- 4. build a pristine pre-fix server, run the agent's reproduction ------
# The pre-fix tree concept is the parent commit's src/t_stream.c checked out
# of the (single-commit, unreachable-fix) clone and rebuilt incrementally.
# The agent's reproduction is run TWICE against the SAME path
# (/app/src/src/redis-server) and the SAME environment: once while the tree
# carries the genuine pre-fix source (must print VERDICT: BUGGY) and once
# after the agent's file is restored and rebuilt (must print VERDICT:
# FIXED). Nothing other than the real behaviour of the binary differs
# between the two runs, so a hard-coded or environment-sniffing
# reproduction is caught. The tree the rest of the verifier sees is again
# exactly the agent's work.
pristine_ok=1
if [ ! -f "$SRC/src/t_stream.c" ]; then
    say_fail "src/t_stream.c missing before pristine rebuild"
    pristine_ok=0
else
    cp "$SRC/src/t_stream.c" /tmp/pc/agent_t_stream.c
    if ! git -C "$SRC" show "${PARENT_SHA}:src/t_stream.c" > "$SRC/src/t_stream.c" 2>/tmp/pc/gitshow.log; then
        say_fail "could not check out parent src/t_stream.c from the clone"
        pristine_ok=0
    fi
fi
if [ "$pristine_ok" = 1 ]; then
    if ! ( cd "$SRC" && make -j1 > /tmp/pc/make_pristine.log 2>&1 ); then
        say_fail "pristine (parent) tree does not build"
        tail -n 10 /tmp/pc/make_pristine.log >&2
        pristine_ok=0
    else
        echo "PASS [pristine] rebuilt genuine pre-fix server from parent source"
    fi
fi

repro_bad=1
repro_good=1
if [ "$pristine_ok" = 1 ] && [ -x /app/reproduce.sh ]; then
    pkill -f '/app/src/src/redis-server' 2>/dev/null || true
    pkill -f 'redis-server.*--port' 2>/dev/null || true
    sleep 0.5
    # 4a. the tree currently is the genuine pre-fix source: must observe it
    ( cd /tmp/pc && REDIS_PORT=6397 \
        timeout 240 /app/reproduce.sh > /tmp/pc/repro_buggy.out 2>&1 )
    rc=$?
    vb=$(verdict_of < /tmp/pc/repro_buggy.out)
    if [ "$rc" -eq 0 ] && [ "$vb" = "VERDICT: BUGGY" ]; then
        echo "PASS [repro] agent reproduction detects the bug on the pristine pre-fix server"
        repro_bad=0
    else
        echo "FAIL [repro] against the pristine pre-fix server expected 'VERDICT: BUGGY' (rc=$rc, got '${vb:-<none>}'):"
        tail -n 12 /tmp/pc/repro_buggy.out | sed 's/^/    /'
        repro_bad=1
    fi
    pkill -f '/app/src/src/redis-server' 2>/dev/null || true
    pkill -f 'redis-server.*--port' 2>/dev/null || true
    sleep 0.5
    # restore the agent's file and rebuild it back
    cp /tmp/pc/agent_t_stream.c "$SRC/src/t_stream.c"
    if ! ( cd "$SRC" && make -j1 > /tmp/pc/make_restore.log 2>&1 ); then
        say_fail "agent's tree failed to rebuild after pristine pass"
        tail -n 10 /tmp/pc/make_restore.log >&2
    fi
    # 4b. the tree is the agent's repaired source again: must see the fix
    ( cd /tmp/pc && REDIS_PORT=6396 timeout 240 /app/reproduce.sh > /tmp/pc/repro_fixed.out 2>&1 )
    rc=$?
    vf=$(verdict_of < /tmp/pc/repro_fixed.out)
    if [ "$rc" -eq 0 ] && [ "$vf" = "VERDICT: FIXED" ]; then
        echo "PASS [repro] agent reproduction shows the fix on the rebuilt server"
        repro_good=0
    else
        echo "FAIL [repro] against the rebuilt server expected 'VERDICT: FIXED' (rc=$rc, got '${vf:-<none>}'):"
        tail -n 12 /tmp/pc/repro_fixed.out | sed 's/^/    /'
        repro_good=1
    fi
    pkill -f '/app/src/src/redis-server' 2>/dev/null || true
    pkill -f 'redis-server.*--port' 2>/dev/null || true
    sleep 0.5
else
    say_fail "reproduction axis skipped (missing deliverable or pristine build)"
fi
[ "$repro_bad" = 0 ] || say_fail "reproduction did not report BUGGY on the pre-fix server"
[ "$repro_good" = 0 ] || say_fail "reproduction did not report FIXED on the rebuilt server"

# ------------ 5. the project's own regression test (from /opt/golden) -------
golden_ok=0
if [ -f /opt/golden/stream-cgroups.tcl ]; then
    gs=$(sha256sum < /opt/golden/stream-cgroups.tcl | cut -d' ' -f1)
    if [ "$gs" != "$GOLDEN_SHA" ]; then
        echo "FAIL [golden] integrity mismatch: sha256 $gs != $GOLDEN_SHA (tampering detected)"
        say_fail "golden regression test failed integrity check"
        golden_ok=0
    else
        cp /opt/golden/stream-cgroups.tcl "$SRC/tests/unit/type/stream-cgroups.tcl"
        ( cd "$SRC" && ./runtest --single unit/type/stream-cgroups --only "$GOLDEN_NAME" > /tmp/pc/golden.log 2>&1 )
        grc=$?
        # restore the parent's own stream-cgroups.tcl from the pinned commit
        ( cd "$SRC" && git show "${PARENT_SHA}:tests/unit/type/stream-cgroups.tcl" > tests/unit/type/stream-cgroups.tcl \
           && git diff --quiet -- tests/unit/type/stream-cgroups.tcl )
        drc=$?
        if [ "$grc" -eq 0 ] \
                && grep -q "All tests passed" /tmp/pc/golden.log \
                && grep -q "\[ok\]: $GOLDEN_NAME" /tmp/pc/golden.log; then
            golden_ok=1
            echo "PASS [golden] fix-commit regression test passed via runtest"
        else
            echo "FAIL [golden] regression test did not pass (grc=$grc, restore_rc=$drc)"
            tail -n 12 /tmp/pc/golden.log
        fi
        if [ "$drc" -ne 0 ]; then
            say_fail "tests/unit/type/stream-cgroups.tcl not restored to the upstream version"
        fi
    fi
else
    echo "FAIL [golden] /opt/golden/stream-cgroups.tcl missing; not run"
fi
[ "$golden_ok" = 1 ] || say_fail "golden regression test failed"

# ------------------ 6. authored hidden cases, via runtest -------------------
hidden_ok=1
for casedir in /tests/hidden/*/; do
    [ -d "$casedir" ] || continue
    name=$(basename "$casedir")
    tclfile=$(ls "$casedir"/*.tcl 2>/dev/null | head -1)
    [ -n "$tclfile" ] || { echo "FAIL [hidden/$name] no .tcl file"; hidden_ok=0; continue; }
    hgot=$(sha256sum < "$tclfile" | cut -d' ' -f1)
    hwant=$(printf '%b' "$HIDDEN_SHA" | awk -F: -v n="$name" '$1==n{print $2}')
    if [ -z "$hwant" ]; then
        echo "FAIL [hidden/$name] not in recorded digest list (sha256 $hgot)"; hidden_ok=0; continue
    fi
    if [ "$hgot" != "$hwant" ]; then
        echo "FAIL [hidden/$name] integrity mismatch: sha256 $hgot != $hwant (tampering detected)"
        hidden_ok=0; continue
    fi
    cp "$tclfile" "$SRC/tests/unit/type/zz-hidden-$name.tcl"
    ( cd "$SRC" && ./runtest --single "unit/type/zz-hidden-$name" > "/tmp/pc/h_$name.log" 2>&1 )
    hrc=$?
    rm -f "$SRC/tests/unit/type/zz-hidden-$name.tcl"
    if [ "$hrc" -eq 0 ] && grep -q "All tests passed" "/tmp/pc/h_$name.log"; then
        echo "PASS [hidden/$name] runtest green"
    else
        echo "FAIL [hidden/$name] runtest exit $hrc"
        grep -E "\[err\]" "/tmp/pc/h_$name.log" | head -5
        hidden_ok=0
    fi
done
[ "$hidden_ok" = 1 ] || say_fail "one or more hidden cases failed"

# --------- 7. the project's own pre-existing stream-cgroups suite -----------
suite_ok=0
( cd "$SRC" && ./runtest --single unit/type/stream-cgroups > /tmp/pc/suite.log 2>&1 )
src=$?
ok_count=$(grep -c '\[ok\]:' /tmp/pc/suite.log || true)
if [ "$src" -eq 0 ] \
        && grep -q "All tests passed" /tmp/pc/suite.log \
        && [ "$ok_count" -ge 170 ] \
        && grep -q "\[ok\]: XGROUP CREATE with ENTRIESREAD larger than stream entries should cap the value" /tmp/pc/suite.log \
        && grep -q "\[ok\]: XGROUP SETID with ENTRIESREAD larger than stream entries should cap the value" /tmp/pc/suite.log; then
    suite_ok=1
    echo "PASS [suite] existing stream-cgroups green ($ok_count asserting tests)"
else
    echo "FAIL [suite] existing stream-cgroups not green (rc=$src, ok=$ok_count)"
    tail -n 12 /tmp/pc/suite.log
fi
[ "$suite_ok" = 1 ] || say_fail "existing stream-cgroups suite failed"

# ---------------- 8. final provenance re-check, after our copies ------------
git -C "$SRC" status --porcelain > /tmp/pc/status_post.txt 2>&1 || say_fail "git status failed (post)"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/pc/status_post.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/t_stream.c' || true)
    if [ -n "$odd" ]; then
        say_fail "post-verify tracked changes outside src/t_stream.c: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/pc/status_post.txt)
if [ -n "$untracked" ]; then
    say_fail "post-verify untracked files: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

if ! pc_audit post; then
    say_fail "provenance blob audit (post) found tampering"
fi

pkill -f '/app/src/src/redis-server' 2>/dev/null || true
pkill -f 'redis-server.*--port' 2>/dev/null || true

# ------------------------------- verdict ------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "REWARD 1: reproduction honest and green, golden+hidden+suite pass, provenance clean"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS verifier failure(s)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0