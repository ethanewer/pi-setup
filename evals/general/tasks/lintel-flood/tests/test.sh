#!/bin/bash
# Verifier for tasks/lintel-flood (executes-deliverable).
#
# Puts the repaired crate at /app/floodgate/ through the full feature matrix:
#   cargo build / cargo test under (default), sliding, bucket, sliding,bucket
# with the verifier's hidden integration tests copied into the crate's own
# test tree, then asserts the shipped suite files and feature declarations
# are still intact. Reward is 1 exactly when every gate is green.
#
# Guarantee a reward on every exit path: without this a verifier that
# aborts while inspecting the agent's deliverable writes nothing at all.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

export CARGO_NET_OFF=true

H=/tests/hidden
CRATE=/app/floodgate

FAIL=false
failadd() { echo "FAIL: $1"; FAIL=true; }

if [ ! -d "$CRATE" ]; then
    failadd "deliverable $CRATE missing"
    echo "0" > /logs/verifier/reward.txt
    echo "REWARD=0"
    exit 0
fi
if [ ! -f "$CRATE/Cargo.toml" ]; then
    failadd "no Cargo.toml under $CRATE"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cd "$CRATE" || { echo "0" > /logs/verifier/reward.txt; exit 0; }

# ---------------------------------------------------------------------------
# 0) Static guards: the feature contract and the test suite must survive.
# ---------------------------------------------------------------------------
feat_section=$(sed -n '/^\[features\]/,/^\[/p' Cargo.toml)
echo "$feat_section" | grep -qE '^sliding\s*=\s*\[\]' || failadd "feature 'sliding' removed or altered in Cargo.toml"
echo "$feat_section" | grep -qE '^bucket\s*=\s*\[\]' || failadd "feature 'bucket' removed or altered in Cargo.toml"
echo "$feat_section" | grep -qE '^default\s*=\s*\[\]' || failadd "default feature set changed in Cargo.toml"
for t in gates single dual; do
    [ -f "tests/$t.rs" ] || failadd "shipped test file tests/$t.rs missing/deleted"
done
if grep -nE '\bunsafe\b' src/*.rs Cargo.toml >/dev/null 2>&1; then
    failadd "crate uses unsafe"
fi

# The instruction forbids deleting, commenting out, or weakening any shipped
# test: the suite must stay green AND COMPLETE under all four combinations.
# Merely checking the files exist let a fix that gutted the spec bodies pass;
# assert the original test functions are still present and enabled, and that
# each file still carries its original bulk of assertions.
shipped_test() { # file fn
    local file=$1 fn=$2
    grep -qE "^[[:space:]]*(#\[test\][[:space:]]+)?fn[[:space:]]+${fn}[[:space:]]*\\(" "tests/$file" \
        && grep -qE "^[[:space:]]*#\\[test\\]" "tests/$file" \
        || failadd "shipped test '${fn}' deleted, commented out, or disabled in tests/$file"
}
assert_floor() { # file min_active_asserts
    local file=$1 min=$2 n
    n=$(sed -E 's://.*$::' "tests/$file" | grep -oE '\bassert\b' | wc -l)
    [ "$n" -ge "$min" ] || failadd "tests/$file weakened: only $n assert statements remain (shipped suite has $min)"
}
for fn in \
    baseline_quota window_start_is_aligned_to_epoch keys_are_independent \
    large_excess_is_clamped_not_overflowed zero_quantity_leaves_state_untouched; do
    shipped_test gates.rs "$fn"
done
assert_floor gates.rs 15
for fn in \
    respects_capacity_across_window events_age_out_exactly_at_window_edge \
    denied_probes_do_not_record quantity_beyond_capacity_reports_zero_when_empty \
    clock_going_backwards_is_clamped consumes_on_grant_and_accrues_with_time \
    idle_refill_saturates_at_capacity denied_probes_change_no_state \
    huge_quantity_ready_value_is_clamped; do
    shipped_test single.rs "$fn"
done
assert_floor single.rs 28
for fn in \
    admits_when_both_strategies_admit sliding_denial_dominates_even_when_bucket_grants \
    bucket_denial_dominates_even_when_sliding_admits both_deny_and_the_larger_delay_wins \
    both_deny_and_a_larger_bucket_retry_wins recovery_after_the_reported_delay \
    zero_quantity_is_admitted_and_records_nothing keys_are_accounted_independently; do
    shipped_test dual.rs "$fn"
done
assert_floor dual.rs 20

# ---------------------------------------------------------------------------
# 1) Inject the hidden integration tests into the crate's test tree.
# ---------------------------------------------------------------------------
cp "$H/dual_edges.rs"      tests/zz_hidden_dual.rs     || failadd "cannot copy hidden dual_edges.rs"
cp "$H/single_edges.rs"    tests/zz_hidden_single.rs   || failadd "cannot copy hidden single_edges.rs"
cp "$H/counter_edges.rs"   tests/zz_hidden_counter.rs  || failadd "cannot copy hidden counter_edges.rs"

# ---------------------------------------------------------------------------
# 2) The full feature matrix: build and test every combination.
# ---------------------------------------------------------------------------
combo_build() { # combo
    local combo=$1 log=/tmp/flood-build.log
    if [ -z "$combo" ]; then
        cargo build >"$log" 2>&1
    else
        cargo build --features "$combo" >"$log" 2>&1
    fi
}
combo_test() { # combo
    local combo=$1 log=/tmp/flood-test.log
    if [ -z "$combo" ]; then
        cargo test >"$log" 2>&1
    else
        cargo test --features "$combo" >"$log" 2>&1
    fi
}

for combo in "" "sliding" "bucket" "sliding,bucket"; do
    label="$combo"; [ -z "$label" ] && label="default"
    if combo_build "$combo"; then
        :
    else
        failadd "cargo build [$label] failed"
        grep -E "^error|panicked" /tmp/flood-build.log | head -5 | sed 's/^/    | /'
    fi
    if combo_test "$combo"; then
        :
    else
        failadd "cargo test [$label] failed"
        grep -E "test result:|panicked|assertion" /tmp/flood-test.log | head -8 | sed 's/^/    | /'
    fi
done

# ---------------------------------------------------------------------------
# 3) The hidden tests must actually have run (not cfg-skipped or vacuous).
# ---------------------------------------------------------------------------
hidden_passes() { # combo file
    local combo=$1 file=$2 log=/tmp/flood-hidden.log passes
    if [ -z "$combo" ]; then
        cargo test --test "$file" >"$log" 2>&1
    else
        cargo test --features "$combo" --test "$file" >"$log" 2>&1
    fi
    if ! grep -qE "test result: ok" "$log"; then
        failadd "hidden test $file [$combo] did not pass"
        tail -6 "$log" | sed 's/^/    | /'
        return
    fi
    passes=$(sed -nE 's/^test result: ok\. ([0-9]+) passed.*/\1/p' "$log" | head -1)
    if [ -z "$passes" ] || [ "$passes" -eq 0 ] 2>/dev/null; then
        failadd "hidden test $file [$combo] ran no tests (vacuous)"
    fi
}
hidden_passes "sliding,bucket" zz_hidden_dual
hidden_passes "sliding"        zz_hidden_single
hidden_passes "bucket"         zz_hidden_single
hidden_passes ""               zz_hidden_counter

# ---------------------------------------------------------------------------
# Finish: write the reward.
# ---------------------------------------------------------------------------
if [ "$FAIL" = true ]; then
    echo "0" > /logs/verifier/reward.txt
else
    echo "1" > /logs/verifier/reward.txt
fi
echo "REWARD=$(cat /logs/verifier/reward.txt)"
exit 0