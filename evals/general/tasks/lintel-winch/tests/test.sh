#!/bin/bash
# Verifier for lintel-winch (executes-deliverable).
#
# Executes the deliverable crate /app/lwrecord/ twice:
#   1. greps the crate for the forbidden `unsafe` keyword and runs the
#      shipped cargo test suite (must be green, all tests run);
#   2. mounts every hidden test file from /tests/hidden/ into the crate's
#      tests/ directory and re-runs cargo test, so the hidden malformed,
#      truncated and adversarial inputs are asserted against the delivered
#      implementation.
# Reward is 1 iff every step passes, otherwise 0.  A readable failure list is
# printed before the reward is written.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

CRATE=/app/lwrecord/
FAIL=false
failadd(){ echo "FAIL: $1"; FAIL=true; }

if [ ! -f "$CRATE"Cargo.toml ]; then
  failadd "crate /app/lwrecord/ missing (no Cargo.toml)"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# ---- 1a) forbidden keyword ------------------------------------------------
if grep -rn "unsafe" "$CRATE"src "$CRATE"tests "$CRATE"Cargo.toml "$CRATE"README.md 2>/dev/null; then
  failadd "crate contains the forbidden keyword 'unsafe'"
fi

# ---- 1b) shipped test suite must run and pass ------------------------------
if ! ( cd "$CRATE" && cargo test --offline ) >/tmp/lw_shipped.log 2>&1; then
  failadd "shipped cargo test suite did not pass"
  tail -30 /tmp/lw_shipped.log
else
  shipped_passed=$(grep -F "test result: ok." /tmp/lw_shipped.log | awk '{for (i=1; i<=NF; i++) if ($i ~ /^passed/ && $(i-1) ~ /^[0-9]+$/) s += $(i-1)} END {print s+0}')
  if [ -z "$shipped_passed" ] || [ "$shipped_passed" -lt 17 ]; then
    failadd "shipped suite ran too few tests (passed=$shipped_passed, want >= 17)"
  fi
fi

# ensure the shipped tests were not neutered: they must still be present with
# their full case counts
r_cases=$(grep -c '^#\[test\]' "$CRATE"tests/roundtrip.rs 2>/dev/null)
e_cases=$(grep -c '^#\[test\]' "$CRATE"tests/errors.rs 2>/dev/null)
if [ "$r_cases" -lt 7 ] || [ "$e_cases" -lt 10 ]; then
  failadd "shipped test files were weakened (roundtrip=$r_cases/7 errors=$e_cases/10)"
fi

# ---- 2) hidden generalization cases ----------------------------------------
H=/tests/hidden
mounted=0
if [ -d "$H" ]; then
  for case in "$H"/*/; do
    [ -d "$case" ] || continue
    cname=$(basename "$case")
    for f in "$case"*.rs; do
      [ -f "$f" ] || continue
      cp "$f" "$CRATE"tests/zz_hh_${cname}_$(basename "$f")
      mounted=$((mounted + 1))
    done
  done
fi
if [ "$mounted" -lt 2 ]; then
  failadd "expected >= 2 hidden test files to mount, found $mounted"
fi

if ! ( cd "$CRATE" && cargo test --offline ) >/tmp/lw_hidden.log 2>&1; then
  failadd "cargo test with hidden files did not pass"
  tail -40 /tmp/lw_hidden.log
else
  hidden_passed=$(grep -F "test result: ok." /tmp/lw_hidden.log | awk '{for (i=1; i<=NF; i++) if ($i ~ /^passed/ && $(i-1) ~ /^[0-9]+$/) s += $(i-1)} END {print s+0}')
  if [ -z "$hidden_passed" ] || [ "$hidden_passed" -lt 31 ]; then
    failadd "hidden run executed too few tests (passed=$hidden_passed, want >= 31)"
  fi
fi

if $FAIL; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

echo "ALL PASS"
echo "1" > /logs/verifier/reward.txt
exit 0
