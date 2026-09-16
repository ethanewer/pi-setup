#!/bin/bash
# Verifier for cistern-bell (real upstream tmux bug: malformed relative
# target offsets such as +foo / -0 are silently accepted instead of rejected).
#
# Reward is 1 only if, in order:
#   1. /app/tmux is still the pinned upstream commit (73db0a54...) and its
#      working tree differs from that commit ONLY in cmd-find.c (no commits,
#      no other tracked file touched, project test scripts untouched);
#   2. /app/tmux/tmux is a real rebuilt ELF binary (not a symlink), and it is
#      newer than the source file the fix requires -- i.e. the agent rebuilt
#      after changing the source;
#   3. the project's own regression scripts for this behaviour
#      (regress/targets.sh, regress/targets-panes.sh, pristine copies that
#      the image extracted at build time into /opt/golden from the upstream
#      merge commit d44bfda2) pass against the agent's binary, and the copies
#      checked into the tree are byte-identical to the pristine ones;
#   4. a subset of the project's pre-existing regress suite that exercises
#      unrelated subsystems also passes against the agent's binary (no
#      regression from the fix);
#   5. every authored hidden case passes against the agent's binary.
# A container where no agent ran (nop) fails step 1 (working tree untouched)
# and scores 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0
TM=/app/tmux
BIN=/app/tmux/tmux
PIN=73db0a54e5ae5abf80bb790829222c9760f60b1d

echo "=== cistern-bell verifier ==="

# ---- 1. provenance: pinned upstream tree, only cmd-find.c modified ---------
if [ ! -d "$TM/.git" ]; then
    echo "FAIL: $TM is not a git checkout (deliverable /app/tmux missing or not a clone)" >&2
    failures=$((failures+1))
else
    head=$(git -C "$TM" rev-parse HEAD 2>&1)
    if [ "$head" != "$PIN" ]; then
        echo "FAIL: /app/tmux HEAD is '$head', expected the pinned upstream commit $PIN" >&2
        failures=$((failures+1))
    else
        echo "provenance: /app/tmux is at the pinned upstream commit"
    fi
    status=$(git -C "$TM" status --porcelain 2>/dev/null)
    if [ "$status" = " M cmd-find.c" ]; then
        echo "provenance: only cmd-find.c modified in the working tree"
    else
        echo "FAIL: working tree differs from the pinned upstream commit in an unexpected way." >&2
        echo "      git status --porcelain reports:" >&2
        printf '%s\n' "${status:-<clean; no change at all>}" | sed 's/^/      | /' >&2
        failures=$((failures+1))
    fi
    # `git update-index --assume-unchanged` (or --skip-worktree) makes git
    # status --porcelain silent about a modified file. Detect the mask: the
    # flags column of `git ls-files -v` shows lowercase 'h' for an
    # assume-unchanged entry and uppercase 'S' for a skip-worktree entry.
    masked=$(git -C "$TM" ls-files -v 2>/dev/null | awk 'substr($0,1,1)=="h" || substr($0,1,1)=="S" {print substr($0,3)}')
    if [ -n "$masked" ]; then
        echo "FAIL: index flags mask working-tree edits on:" >&2
        printf '%s\n' "$masked" | sed 's/^/      | /' >&2
        failures=$((failures+1))
    else
        echo "provenance: no assume-unchanged/skip-worktree masking in the index"
    fi
    # the project's own regression scripts must be byte-identical to upstream.
    # The pristine bytes are pinned by SHA-256 (computed from the upstream
    # merge commit d44bfda2, the same extraction the Dockerfile performs) so
    # tampering with /opt/golden cannot weaken the golden run.
    for f in targets.sh targets-panes.sh; do
        case "$f" in
            targets.sh) want_sha=ec3acd53877b645abf848a849fd6dd6b97a7d79142fc599e96e4c56d9a0a1f34 ;;
            targets-panes.sh) want_sha=be45c059315ae2c52a515944a177ee1ab933d31d76b95573ba902ae08394eaa6 ;;
        esac
        if [ -f "$TM/regress/$f" ] && [ -f "/opt/golden/$f" ]; then
            if cmp -s "$TM/regress/$f" "/opt/golden/$f"; then
                echo "provenance: regress/$f matches upstream (untouched)"
            else
                echo "FAIL: regress/$f was modified; the project's test scripts must stay untouched" >&2
                failures=$((failures+1))
            fi
            got_sha=$(sha256sum "/opt/golden/$f" 2>/dev/null | awk '{print $1}')
            if [ "$got_sha" != "$want_sha" ]; then
                echo "FAIL: /opt/golden/$f is not the pristine upstream script (sha256 $got_sha, want $want_sha)" >&2
                failures=$((failures+1))
            else
                echo "provenance: /opt/golden/$f matches the pinned upstream bytes"
            fi
        else
            echo "FAIL: regress/$f or /opt/golden/$f missing" >&2
            failures=$((failures+1))
        fi
    done
fi

# ---- 2. the deliverable binary ---------------------------------------------
if [ ! -x "$BIN" ]; then
    echo "FAIL: deliverable /app/tmux/tmux missing or not executable" >&2
    failures=$((failures+1))
else
    if [ -L "$BIN" ]; then
        echo "FAIL: /app/tmux/tmux is a symlink; must be the real built binary" >&2
        failures=$((failures+1))
    fi
    if ! magic=$(head -c4 "$BIN" 2>/dev/null | od -An -tx1 | tr -d ' \n'); then
        magic=""
    fi
    if [ "$magic" != "7f454c46" ]; then
        echo "FAIL: /app/tmux/tmux is not an ELF executable (magic=$magic)" >&2
        failures=$((failures+1))
    else
        echo "binary: /app/tmux/tmux is a real ELF executable"
    fi
    if [ -f "$TM/cmd-find.c" ] && [ ! "$BIN" -nt "$TM/cmd-find.c" ]; then
        echo "FAIL: /app/tmux/tmux is not newer than cmd-find.c -- rebuild after fixing the source" >&2
        failures=$((failures+1))
    fi
fi

# ---- 3. the project's own regression scripts for this behaviour ------------
# (pristine copies extracted at image build time from the upstream commit that
# contains both the tests and the fix; never part of this task tree)
for f in targets.sh targets-panes.sh; do
    log="/tmp/golden-$f.log"
    if ( cd /opt/golden && TEST_TMUX="$BIN" sh "$f" >"$log" 2>&1 ); then
        echo "golden: $f PASS against the agent's binary"
    else
        echo "FAIL: golden $f FAILED against the agent's binary" >&2
        tail -12 "$log" | sed 's/^/      | /' >&2
        failures=$((failures+1))
    fi
done

# ---- 4. pre-existing regress suite subset (unrelated subsystems) ------------
# These all passed at the unfixed tree and must keep passing after the fix.
for t in check-names command-alias environ has-session-return if-shell-error; do
    log="/tmp/regress-$t.log"
    if ( cd "$TM/regress" && TEST_TMUX="$BIN" sh "$t.sh" >"$log" 2>&1 ); then
        echo "suite: $t.sh PASS"
    else
        echo "FAIL: pre-existing suite test $t.sh failed against the agent's build" >&2
        tail -8 "$log" | sed 's/^/      | /' >&2
        failures=$((failures+1))
    fi
done

# ---- 5. authored hidden cases (inputs the upstream tests do not use) --------
for d in /tests/hidden/*/; do
    c=$(basename "$d")
    log="/tmp/hidden-$c.log"
    if [ -f "$d/run.sh" ]; then
        if ( TEST_TMUX="$BIN" bash "$d/run.sh" >"$log" 2>&1 ); then
            echo "hidden: $c PASS"
        else
            echo "FAIL: hidden case $c failed against the agent's binary" >&2
            tail -15 "$log" | sed 's/^/      | /' >&2
            failures=$((failures+1))
        fi
    else
        echo "FAIL: hidden case $c has no run.sh" >&2
        failures=$((failures+1))
    fi
done

# ---- reward ---------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: ${failures} failure(s) present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0