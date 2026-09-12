#!/bin/bash
# conduit-basin verifier.
#
# Grades a repaired redis tree on four axes:
#  (1) provenance: the clone is still the pinned parent commit, the upstream
#      fix commit is not reachable from it, the ONLY tracked change allowed
#      is src/redis-cli.c, no stray untracked files were added, and the
#      fix is actually implemented in the source;
#  (2) behaviour: the project's own regression test for the bug (the test
#      'bigkeys reports a zero-size key as the biggest key of its type'
#      from the fix commit's tests/integration/redis-cli.tcl, extracted
#      into /opt/golden and never present in the agent's tree) must pass
#      against the rebuilt binary;
#  (3) authored hidden cases that drive the same code path from inputs the
#      upstream test does not use (empty string among other types, several
#      all-empty strings, the --keystats length report, and a non-empty
#      biggest-key guard) must pass, run through the project's runtest;
#  (4) the project's own pre-existing redis-cli integration tests stay
#      green.
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
PARENT_SHA=21ce96878529bf8b31298ec417407c578c1e6278
FIX_SHA=669b2a1316f5b35ecf964281b77c054ff28dc934
GOLDEN_NAME="bigkeys reports a zero-size key as the biggest key of its type"
FAILS=0

say_fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

# ------------------------- 0. deliverables present --------------------------
[ -f "$SRC/src/redis-cli.c" ] || say_fail "source tree missing src/redis-cli.c"
[ -x "$SRC/src/redis-cli" ] || say_fail "redis-cli missing or not executable"
[ -x "$SRC/src/redis-server" ] || say_fail "redis-server missing or not executable"

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

git -C "$SRC" status --porcelain > /tmp/cb_status_pre.txt 2>&1 || say_fail "git status failed in $SRC"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/cb_status_pre.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/redis-cli.c' || true)
    if [ -n "$odd" ]; then
        say_fail "unexpected tracked changes: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/cb_status_pre.txt)
if [ -n "$untracked" ]; then
    say_fail "unexpected untracked files in tree: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

if [ -z "$(git -C "$SRC" diff -- src/redis-cli.c 2>/dev/null || true)" ]; then
    say_fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi

# ------------------- 2. stop stray servers left by the agent ----------------
pkill -f '/app/src/src/redis-server' 2>/dev/null || true
pkill -f 'redis-server.*--port' 2>/dev/null || true
sleep 0.5

# ----------------- 3. incremental rebuild so the binary reflects the tree ----
if ! ( cd "$SRC" && make -j1 > /tmp/cb_make.log 2>&1 ); then
    say_fail "incremental make failed (tree does not build):"
    tail -n 15 /tmp/cb_make.log >&2
fi
[ -x "$SRC/src/redis-cli" ] || say_fail "redis-cli not produced by make"

# ----------- 4. the project's own regression test (from /opt/golden) --------
# The golden regression test and the authored hidden cases are the ONLY
# behavioural backstops: the parent's own integration/redis-cli suite passes
# on the buggy tree, so a hollowed-out golden/hidden axis would let a hostile
# agent earn 1 with the bug intact. /opt/golden lives inside the (root-)
# writable image and an agent phase edit of it was observed to persist into
# this phase, so verify the bytes we are about to run against digests
# recorded at authoring time before trusting them. /tests is (re)injected
# per phase, but the same digest check keeps it honest wherever it lives.
golden_ok=0
GOLDEN_SHA=8b2259d601f3621cdc26321f983ef648d787984925ae134888ee478380ba2ea4
if [ -f /opt/golden/redis-cli.tcl ]; then
    gs=$(sha256sum < /opt/golden/redis-cli.tcl | cut -d' ' -f1)
    if [ "$gs" != "$GOLDEN_SHA" ]; then
        echo "FAIL [golden] integrity mismatch: sha256 $gs != $GOLDEN_SHA (tampering detected)"
        say_fail "golden regression test failed integrity check"
        golden_integrity_ok=0
    else
        golden_integrity_ok=1
    fi
else
    say_fail "golden regression test missing from image"
    golden_integrity_ok=0
fi
if [ "$golden_integrity_ok" = 1 ]; then
    cp /opt/golden/redis-cli.tcl "$SRC/tests/integration/redis-cli.tcl"
    ( cd "$SRC" && ./runtest --single integration/redis-cli --only "$GOLDEN_NAME" > /tmp/cb_golden.log 2>&1 )
    grc=$?
    # restore the parent's own redis-cli.tcl from the pinned commit
    ( cd "$SRC" && git show "${PARENT_SHA}:tests/integration/redis-cli.tcl" > tests/integration/redis-cli.tcl \
       && git diff --quiet -- tests/integration/redis-cli.tcl )
    drc=$?
    if [ "$grc" -eq 0 ] \
            && grep -q "All tests passed" /tmp/cb_golden.log \
            && grep -q "\[ok\]: $GOLDEN_NAME" /tmp/cb_golden.log; then
        golden_ok=1
        echo "PASS [golden] fix-commit regression test passed via runtest"
    else
        echo "FAIL [golden] regression test did not pass (grc=$grc, restore_rc=$drc)"
        tail -n 15 /tmp/cb_golden.log
    fi
    if [ "$drc" -ne 0 ]; then
        say_fail "tests/integration/redis-cli.tcl not restored to the upstream version"
    fi
else
    echo "FAIL [golden] /opt/golden/redis-cli.tcl missing or tampered; not run"
fi
[ "$golden_ok" = 1 ] || say_fail "golden regression test failed"

# ---------------- 5. authored hidden cases, run through runtest --------------
hidden_ok=1
HIDDEN_SHA="case-guard:78ad76e4f003183453750a3925bec04d5df53316a22d350880d052683c9b9410\ncase-manyempty:69028f38b228e3317a544945bae06ae374c80e578789634694691ed48d0c73b0\ncase-types:0804b27007a159776e3d319a4a2b19c27f0fd9802eaafaea22a34bc3751ab994\ncase-keystats:a712c3d3ce0ae38dba43724d8f471f2ff3432162a8c376c9a825fb7fdfa7a895"
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
    cp "$tclfile" "$SRC/tests/integration/zz-hidden-$name.tcl"
    ( cd "$SRC" && ./runtest --single "integration/zz-hidden-$name" > "/tmp/cb_h_$name.log" 2>&1 )
    hrc=$?
    rm -f "$SRC/tests/integration/zz-hidden-$name.tcl"
    if [ "$hrc" -eq 0 ] && grep -q "All tests passed" "/tmp/cb_h_$name.log"; then
        echo "PASS [hidden/$name] runtest green"
    else
        echo "FAIL [hidden/$name] runtest exit $hrc"
        grep -E "\[err\]" "/tmp/cb_h_$name.log" | head -5
        hidden_ok=0
    fi
done
if [ "$hidden_ok" != 1 ]; then
    say_fail "one or more hidden cases failed"
fi

# -------- 6. the project's own existing redis-cli integration suite ---------
suite_ok=0
( cd "$SRC" && ./runtest --single integration/redis-cli > /tmp/cb_suite.log 2>&1 )
src=$?
ok_count=$(grep -c '\[ok\]:' /tmp/cb_suite.log || true)
if [ "$src" -eq 0 ] \
        && grep -q "All tests passed" /tmp/cb_suite.log \
        && [ "$ok_count" -ge 10 ] \
        && grep -q "\[ok\]: keystats on empty database should not produce garbage stats" /tmp/cb_suite.log; then
    suite_ok=1
    echo "PASS [suite] existing integration/redis-cli green ($ok_count tests)"
else
    echo "FAIL [suite] existing integration/redis-cli not green (rc=$src, ok=$ok_count)"
    tail -n 15 /tmp/cb_suite.log
fi
[ "$suite_ok" = 1 ] || say_fail "existing integration/redis-cli suite failed"

# ---------------- 7. final provenance re-check, after our copies ------------
git -C "$SRC" status --porcelain > /tmp/cb_status_post.txt 2>&1 || say_fail "git status failed (post)"
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/cb_status_post.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'src/redis-cli.c' || true)
    if [ -n "$odd" ]; then
        say_fail "post-verify tracked changes outside src/redis-cli.c: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/cb_status_post.txt)
if [ -n "$untracked" ]; then
    say_fail "post-verify untracked files: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

pkill -f '/app/src/src/redis-server' 2>/dev/null || true

# ------------------------------- verdict ------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "REWARD 1: zero-size biggest key reported, golden+hidden+suite green, provenance clean"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS verifier failure(s)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0