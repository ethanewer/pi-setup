#!/bin/bash
#
# marble-ridge verifier. Executes the deliverable /app/gated_norm.py under
# TRITON_INTERPRET=1: first a static inspection of the kernel bodies (tl-ops
# only, no sum helper), then a hidden shape/mode battery that re-invokes
# gated_layernorm and compares against a pure-torch reference computed here.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path
# (EXIT trap).
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

export TRITON_INTERPRET=1

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

log() { echo "marble-ridge verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverable present and importable.
# ---------------------------------------------------------------------------
if [ ! -s /app/gated_norm.py ]; then
  overall=0; msgs="$msgs missing:gated_norm.py"
else
  if ! $TIMEOUT_CMD 120 python3 -c "import sys; sys.path.insert(0, '/app'); import gated_norm" \
        >/tmp/fg_import.log 2>&1; then
    overall=0; msgs="$msgs import:failed"
    tail -5 /tmp/fg_import.log >&2 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 2. Kernel-body inspection: triton.language ops only, explicit reductions
#    (no tl.sum / triton.language.sum / .sum( anywhere; no built-in sum,
#    torch, numpy, or math inside @triton.jit bodies).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 60 python3 /tests/hidden/check_source.py >/tmp/fg_src.log 2>&1; then
    overall=0; msgs="$msgs kernel-inspection:failed"
    tail -5 /tmp/fg_src.log >&2 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 3. Hidden shape/mode battery: execute gated_layernorm on edge shapes in
#    both gate modes against the reference formula, tight float32 tolerance.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/probe_shapes/probe.py >/tmp/fg_shapes.log 2>&1; then
    overall=0; msgs="$msgs shapes:failed"
    tail -8 /tmp/fg_shapes.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0
