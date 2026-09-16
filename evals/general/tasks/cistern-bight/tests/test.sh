#!/bin/bash
# Verifier for cistern-bight: proves the agent's fix in the real clap-rs/clap
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit, every tracked file except the single long/short-help source file is
# byte-identical to it, no stray untracked files, and the object store holds
# nothing beyond the pinned commit), (2) requiring /app/summary.md, (3)
# planting the upstream project's own regression test for this bug (help.rs
# as at the fix commit, extracted at image build time into /opt/golden) plus
# three authored hidden test modules, (4) rebuilding the project's own
# builder test suite offline, and (5) running EVERY builder suite binary end
# to end, demanding that all pass AND that each required regression/hidden
# test function actually ran and passed.
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

PARENT=fb9435d026ab011c9071ca92eeab738b9b30ca13
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit (no commits added,
#    and nothing can hide work from the blob-level scope check below).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the long/short help-layout decision in src/builder/command.rs,
#    discovered by the agent, not named here). This is a CONTENT check, not a
#    git-status check: we hash the actual bytes of every tracked file on disk
#    against the pinned commit's own blob, so assume-unchanged/skip-worktree
#    tricks cannot hide a dirty file, and we refuse any untracked
#    non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/builder/command.rs) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) belt: the object store must hold nothing beyond the pinned parent commit
#    (no sneaked-in upstream commit, no hidden modifications).
unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see fsck)"
fi

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5) plant the upstream regression test (golden bytes of tests/builder/help.rs
#    from the fix commit, extracted at image build time; never part of this
#    task tree) and the three authored hidden test modules into the builder
#    test suite, wiring the new modules into tests/builder/main.rs like the
#    rest of the crate. The golden file is baked into the image, so the trial
#    user could in principle rewrite it to neutralise the regression test; a
#    pinned hash of the exact bytes extracted from the fix commit catches any
#    such tampering before the tree is modified.
GOLDEN_SHA=$(sha256sum /opt/golden/help.rs | cut -d' ' -f1)
[ "$GOLDEN_SHA" = "d4738a4e745c4d1f95d71fc410bb76f00bc3188b182199c5c0a1fcf46ff4831c" ] || \
    fail "golden regression test /opt/golden/help.rs was tampered with (sha256 $GOLDEN_SHA)"
cp /opt/golden/help.rs tests/builder/help.rs || fail "cannot plant golden regression test"
cp /tests/hidden/hidden-pv/zz_hidden_pv.rs tests/builder/zz_hidden_pv.rs || fail "cannot plant hidden case 1"
cp /tests/hidden/longhelp-boundary/zz_longhelp_boundary.rs tests/builder/zz_longhelp_boundary.rs || fail "cannot plant hidden case 2"
cp /tests/hidden/visible-guard/zz_visible_guard.rs tests/builder/zz_visible_guard.rs || fail "cannot plant hidden case 3"
for m in zz_hidden_pv zz_longhelp_boundary zz_visible_guard; do
    grep -q "^mod ${m};" tests/builder/main.rs || printf '\nmod %s;\n' "$m" >> tests/builder/main.rs
done

# 6) rebuild the project's own builder test suite, offline (warm caches).
if ! cargo test --no-run -p clap > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo test --no-run -p clap failed after planting regression/hidden tests"
fi

# 7) run EVERY builder suite binary end to end; any failing test anywhere in
#    the builder suites fails the task. (Several builder-* binaries can exist
#    when the target's content hash changed; all of them must be green.)
SUITES=/logs/verifier/suites.log
: > "$SUITES"
for BIN in target/debug/deps/builder-*; do
    case "$BIN" in *.d) continue ;; esac
    if ! "$BIN" > /tmp/suite.out 2>&1; then
        echo "suite binary $BIN failed; tail:" >> "$LOG"
        tail -20 /tmp/suite.out >> "$LOG"
        fail "builder suite binary $BIN exited non-zero (see $LOG)"
    fi
    cat /tmp/suite.out >> "$SUITES"
done

# 8) belt: every required test must actually have RUN and PASSED in one of
#    the suites (a neutralised/skipped run or a sabotaged test list would
#    leave no "::<fn> ... ok" line even though suites exited 0).
for t in \
    hidden_possible_vals \
    hidden_pv_named_opt_short_flag \
    hidden_pv_named_opt_long_flag \
    hidden_pv_long_help_long_flag \
    hidden_pv_long_help_short_flag \
    visible_pos_vals_help_still_long \
    visible_opt_vals_help_still_long; do
    if ! grep -q "::${t} \.\.\. ok" "$SUITES"; then
        fail "required test ${t} did not run and pass in the builder suites (see $SUITES)"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0