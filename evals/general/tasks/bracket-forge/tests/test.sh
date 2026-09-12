#!/bin/bash
# Verifier for bracket-forge: proves the agent's fix in the real rust-lang/regex
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit, the on-disk bytes of every tracked file except the single
# slot-accounting source file hash to the pinned commit's own blob, and no
# stray untracked non-ignored file exists), (2) requiring /app/summary.md,
# (3) verifying the image's /opt/golden/regression.rs is byte-exact the fix
# commit's blob (sha256 is deterministic for the immutable git blob),
# (4) planting the upstream regression test from /opt/golden plus the three
# authored hidden test modules, (5) rebuilding the project's own `integration`
# test target offline with cargo, (6) locating the freshly rebuilt test binary
# and PROVING it contains every planted test name (--list) so that no wrapper,
# shim or stubbed cargo can fake a run, and (7) executing that real binary
# DIRECTLY (never through cargo) and demanding every required test actually
# passed.
#
# Why direct execution: the verifier used to run `cargo test` and grep its
# stdout for "ok" lines. A `cargo` wrapper that prints the demanded lines
# without building anything then earned reward 1 on an untouched tree (author
# review reproduced that: replaced /opt/cargo/bin/cargo with a shim printing
# the 7 demanded "ok" lines, tree untouched, reward 1). The binary-level
# checks below close that: the graded tests are compiled into the reconstruction
# of the project's own test binary by the real toolchain, and an agent cannot
# produce a binary that --lists the planted names without the real source.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u

GOLDEN_SHA256=7678ef4d065103cf822d548c24e323a605de502abb9c81b22ebf0e9f9e8eeea4

mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=5ea3eb1e95f0338e283f5f0b4681f0891a1cd836
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# 0) the upstream regression test baked into the image must be byte-exact the
#    fix commit's blob (sha256 deterministic: the file is `git show <fix>:...`
#    output at image build time). A tampered/stubbed golden test fails here.
if [ ! -f /opt/golden/regression.rs ]; then
    fail "/opt/golden/regression.rs is missing"
fi
got=$(sha256sum /opt/golden/regression.rs | awk '{print $1}')
if [ "$got" != "$GOLDEN_SHA256" ]; then
    fail "golden regression.rs hash $got != expected $GOLDEN_SHA256 (tampered stub cannot stand in for the upstream test)"
fi

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: content check of every tracked file on disk against the pinned
#    commit's own blob; only regex-automata/src/dfa/onepass.rs may differ;
#    refuse any untracked non-ignored file (target/ and Cargo.lock are
#    gitignored by upstream).
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        regex-automata/src/dfa/onepass.rs) : ;;
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

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time; never part of this task tree) and the three
#    authored hidden test modules, wiring them into dfa/onepass/mod.rs
#    alongside the existing suite module.
ONEPASS_TESTS=/app/src/regex-automata/tests/dfa/onepass
cd /app/src || fail "/app/src is missing"
cp /opt/golden/regression.rs "$ONEPASS_TESTS/regression.rs" || fail "cannot plant golden regression test"
cp /tests/hidden/hidden-multipattern/zz_hidden_multipattern.rs "$ONEPASS_TESTS/zz_hidden_multipattern.rs" || fail "cannot plant hidden case 1"
cp /tests/hidden/hidden-zero-repeat/zz_hidden_zero_repeat.rs "$ONEPASS_TESTS/zz_hidden_zero_repeat.rs" || fail "cannot plant hidden case 2"
cp /tests/hidden/hidden-empty-extra/zz_hidden_empty_extra.rs "$ONEPASS_TESTS/zz_hidden_empty_extra.rs" || fail "cannot plant hidden case 3"
printf 'mod regression;\nmod zz_hidden_multipattern;\nmod zz_hidden_zero_repeat;\nmod zz_hidden_empty_extra;\nmod suite;\n' > "$ONEPASS_TESTS/mod.rs"

# 5) rebuild the project's own integration test target, offline (warm caches).
if ! cargo test --no-run -p regex-automata --test integration > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo test --no-run -p regex-automata --test integration failed after planting regression/hidden tests"
fi

# 6) locate the freshly built test binary — the newest target/debug/deps/
#    integration-* whose OWN --list actually lists a planted hidden test.
#    A stub cargo that never compiled the planted tests (or a shim that
#    merely printed fake output) cannot produce such a binary: the --list
#    content only exists in a real rebuild of the real integration test
#    crate. Run the binary DIRECTLY (not through cargo) so no wrapper can
#    intercept the actual test executions.
BIN=""
for cand in $(ls -t target/debug/deps/integration-* 2>/dev/null); do
    [ -x "$cand" ] || continue
    if "$cand" --list 2>/dev/null | grep -q "zz_hidden_multipattern::too_many_slots_many_patterns"; then
        BIN="$cand"; break
    fi
done
if [ -z "$BIN" ]; then
    fail "no rebuilt integration test binary lists the planted hidden tests (a fake build or wrapper cannot pass)"
fi

# 6b) belt: the binary's own test list must contain EVERY planted test name
#     (upstream golden + hidden). Missing any name proves the run was
#     not executed against the tests that are graded.
LIST="$("$BIN" --list 2>&1)"
for t in \
    regression::zero_repetition_capture_group \
    regression::too_many_slots_normal_pattern \
    zz_hidden_multipattern::too_many_slots_many_patterns \
    zz_hidden_zero_repeat::zero_repetition_group_between_groups \
    zz_hidden_empty_extra::too_many_slots_empty_match_pattern; do
    if ! printf '%s' "$LIST" | grep -q "$t"; then
        fail "rebuilt test binary does not contain planted test $t"
    fi
done

# 7) run the REAL binary directly against the regression tests, the hidden
#    tests and the project's own existing one-pass suite, and demand that
#    each required test actually ran and passed (libtest prints
#    "test dfa::onepass::<name> ... ok" for every executed test; any panic or
#    failure makes the binary exit non-zero).
OUT=/logs/verifier/tests.log
: > "$OUT"
"$BIN" --test-threads=1 \
    dfa::onepass::regression \
    dfa::onepass::zz_hidden_multipattern \
    dfa::onepass::zz_hidden_zero_repeat \
    dfa::onepass::zz_hidden_empty_extra \
    dfa::onepass::suite >> "$OUT" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "integration test binary exited $rc; tail:" >> "$LOG"
    tail -40 "$OUT" >> "$LOG"
    fail "integration test binary exited non-zero (see $LOG)"
fi

for t in \
    zero_repetition_capture_group \
    too_many_slots_normal_pattern \
    too_many_slots_many_patterns \
    zero_repetition_group_between_groups \
    too_many_slots_empty_match_pattern \
    suite::default \
    suite::starts_for_each_pattern; do
    if ! grep -q "::${t} \.\.\. ok" "$OUT"; then
        fail "required test ${t} did not run and pass (see $OUT)"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0