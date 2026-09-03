#!/bin/bash
#
# tl-crown-pareto verifier.
# Executes the deliverable /app/nsga.py (CLI: python3 nsga.py <params.json>
# <result.json>) against hidden params (different seeds, sizes, and a
# 3-objective case) and runs the independent probe: feasibility + objective
# recompute, mutual non-domination, exact hypervolume consistency, and the
# documented quality gates (knapsack HV vs independent reference NSGA-II,
# saddle IGD vs random-search baseline, triplane front property). Also a
# static source check for the core NSGA-II components.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path.
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "tl-crown-pareto verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverable present.
# ---------------------------------------------------------------------------
if [ ! -s /app/nsga.py ]; then
  overall=0
  msgs="$msgs missing:nsga.py"
fi

# ---------------------------------------------------------------------------
# 2. Static source check: core NSGA-II components present.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 60 python3 /tests/hidden/probe.py --check-source \
        >/tmp/cp_source.log 2>&1; then
    overall=0
    msgs="$msgs source-check:failed"
    tail -5 /tmp/cp_source.log >&2 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 3. Hidden cases: execute /app/nsga.py on each hidden params file and run
#    the independent probe (recompute, non-domination, hypervolume, gates).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/probe.py /tests/hidden/cases \
        >/tmp/cp_probe.log 2>&1; then
    overall=0
    msgs="$msgs hidden-cases:failed"
    tail -15 /tmp/cp_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0