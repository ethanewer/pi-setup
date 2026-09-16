#!/bin/bash
# bracket-flood verifier.
#
# Grades a repaired redis tree on three axes:
#  (1) provenance: the clone is still the pinned parent commit, the upstream
#      fix commit is not reachable from it, the ONLY tracked change allowed
#      is src/cluster.c, and no stray untracked files were added;
#  (2) behaviour: the project's own regression test for the bug (the test
#      'RESTORE with a TTL that overflows when added to the current time'
#      from the fix commit's tests/unit/dump.tcl, extracted into
#      /opt/golden and never present in the agent's tree) must pass against
#      the rebuilt binary, and two authored hidden cases that drive the same
#      code path from inputs the upstream test does not use must pass;
#  (3) the project's own existing unit/dump suite (DUMP/RESTORE round-trips,
#      TTL handling, MIGRATE) must stay green.
#
# The verifier runs `make -j1` itself so the binary always reflects the
# agent's tree, then runs every check through the project's own test runner.
#
# Writes 1/0 to /logs/verifier/reward.txt. The EXIT trap guarantees that a
# verifier that dies before writing still yields 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
PARENT_SHA=3d15ede58ad862996f9b23d3500cad2a5c7fb0f4
FIX_SHA=48cc562064dbb52ef3f9cc1a5aa32db6811f5871
GOLDEN_NAME="RESTORE with a TTL that overflows when added to the current time"
FAILS=0

say_fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

# ------------------------- 0. deliverables present --------------------------
[ -f "$SRC/src/cluster.c" ] || say_fail "source tree missing src/cluster.c"
[ -x "$SRC/src/redis-server" ] || say_fail "redis-server missing or not executable"
[ -s /app/diagnosis.md ] || say_fail "/app/diagnosis.md missing or empty"

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

git -C "$SRC" status --porcelain > /tmp/bf_status_pre.txt 2>&1 || say_fail "git status failed in $SRC"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/bf_status_pre.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/cluster.c' || true)
    if [ -n "$odd" ]; then
        say_fail "unexpected tracked changes: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/bf_status_pre.txt)
if [ -n "$untracked" ]; then
    say_fail "unexpected untracked files in tree: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

# ------------------- 2. stop stray servers left by the agent ----------------
pkill -f '/app/src/src/redis-server' 2>/dev/null || true
pkill -f 'redis-server.*--port' 2>/dev/null || true
sleep 0.5

# ---------------- 3. rebuild the binary FORCEFULLY from the shipped source ----
# The trial container runs as root and src/redis-server plus src/*.o are
# gitignored upstream, so an agent could drop a fake/wrapper binary (or a
# tampered object) at src/redis-server: it would be invisible to the provenance
# check and, if made strictly newer than its deps, would survive `make`.
# Forcing make to recompile the RESTORE handler from the CURRENT source and
# relink the binary makes the graded binary necessarily reflect the shipped
# tree, so a buggy source can only produce a buggy binary.
touch "$SRC/src/cluster.c"
rm -f "$SRC/src/redis-server" "$SRC/src/redis-cli"
if ! ( cd "$SRC" && make -j1 > /tmp/bf_make.log 2>&1 ); then
    say_fail "incremental make failed (tree does not build):"
    tail -n 15 /tmp/bf_make.log >&2
fi
# the rebuilt binary must be a genuine ELF binary (magic 7f ELF), not a wrapper
bf_magic=$(head -c 4 "$SRC/src/redis-server" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$bf_magic" != "7f454c46" ]; then
    say_fail "src/redis-server is not a native ELF binary after make (magic='$bf_magic')"
fi

# ----------- 4. the project's own regression test (from /opt/golden) --------
golden_ok=0
if [ -f /opt/golden/dump.tcl ]; then
    # integrity: the regression test must be the unmodified fix-commit file, or
    # an agent could neuter it to a vacuous pass while leaving the bug in place.
    gf=$(sha256sum /opt/golden/dump.tcl | awk '{print $1}')
    if [ "$gf" != "5fc41d76f19c1293c9caaf2644c38863503d300adb650322712250e8775cb22d" ]; then
        say_fail "/opt/golden/dump.tcl was modified (sha256=$gf)"
    fi
    cp /opt/golden/dump.tcl "$SRC/tests/unit/dump.tcl"
    ( cd "$SRC" && ./runtest --single unit/dump --only "$GOLDEN_NAME" > /tmp/bf_golden.log 2>&1 )
    grc=$?
    # restore the parent's own dump.tcl from the pinned commit
    ( cd "$SRC" && git show "${PARENT_SHA}:tests/unit/dump.tcl" > tests/unit/dump.tcl \
       && git diff --quiet -- tests/unit/dump.tcl )
    drc=$?
    if [ "$grc" -eq 0 ] \
            && grep -q "All tests passed" /tmp/bf_golden.log \
            && grep -q "\[ok\]: $GOLDEN_NAME" /tmp/bf_golden.log; then
        golden_ok=1
        echo "PASS [golden] fix-commit regression test passed via runtest"
    else
        echo "FAIL [golden] regression test did not pass (grc=$grc, restore_rc=$drc)"
        tail -n 15 /tmp/bf_golden.log
    fi
    if [ "$drc" -ne 0 ]; then
        say_fail "tests/unit/dump.tcl not restored to the upstream version"
    fi
else
    echo "FAIL [golden] /opt/golden/dump.tcl missing from image"
fi
[ "$golden_ok" = 1 ] || say_fail "golden regression test failed"

# ---------------- 5. authored hidden cases, run through runtest --------------
hidden_ok=1
for casedir in /tests/hidden/*/; do
    [ -d "$casedir" ] || continue
    name=$(basename "$casedir")
    tclfile=$(ls "$casedir"/*.tcl 2>/dev/null | head -1)
    [ -n "$tclfile" ] || { echo "FAIL [hidden/$name] no .tcl file"; hidden_ok=0; continue; }
    cp "$tclfile" "$SRC/tests/unit/zz-hidden-$name.tcl"
    ( cd "$SRC" && ./runtest --single "unit/zz-hidden-$name" > "/tmp/bf_h_$name.log" 2>&1 )
    hrc=$?
    rm -f "$SRC/tests/unit/zz-hidden-$name.tcl"
    if [ "$hrc" -eq 0 ] && grep -q "All tests passed" "/tmp/bf_h_$name.log"; then
        echo "PASS [hidden/$name] runtest green"
    else
        echo "FAIL [hidden/$name] runtest exit $hrc"
        grep -E "\[err\]" "/tmp/bf_h_$name.log" | head -5
        hidden_ok=0
    fi
done
if [ "$hidden_ok" != 1 ]; then
    say_fail "one or more hidden cases failed"
fi

# -------- 6. the project's own existing suite (unit/dump) stays green --------
suite_ok=0
( cd "$SRC" && ./runtest --single unit/dump > /tmp/bf_suite.log 2>&1 )
src=$?
ok_count=$(grep -c '\[ok\]:' /tmp/bf_suite.log || true)
if [ "$src" -eq 0 ] \
        && grep -q "All tests passed" /tmp/bf_suite.log \
        && [ "$ok_count" -ge 8 ] \
        && grep -q "\[ok\]: RESTORE can set an arbitrary expire" /tmp/bf_suite.log; then
    suite_ok=1
    echo "PASS [suite] unit/dump green ($ok_count tests)"
else
    echo "FAIL [suite] unit/dump not green (rc=$src, ok=$ok_count)"
    tail -n 15 /tmp/bf_suite.log
fi
[ "$suite_ok" = 1 ] || say_fail "existing unit/dump suite failed"

# ---------------- 7. final provenance re-check, after our copies ------------
git -C "$SRC" status --porcelain > /tmp/bf_status_post.txt 2>&1 || say_fail "git status failed (post)"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/bf_status_post.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/cluster.c' || true)
    if [ -n "$odd" ]; then
        say_fail "post-verify tracked changes outside src/cluster.c: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/bf_status_post.txt)
if [ -n "$untracked" ]; then
    say_fail "post-verify untracked files: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

# ------------------------ 8. diagnosis write-up sanity -----------------------
if ! grep -qi 'restore' /app/diagnosis.md 2>/dev/null; then
    say_fail "/app/diagnosis.md does not mention RESTORE"
fi

pkill -f '/app/src/src/redis-server' 2>/dev/null || true

# ------------------------------- verdict ------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "REWARD 1: overflow guarded, golden+hidden+suite green, provenance clean"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS verifier failure(s)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0