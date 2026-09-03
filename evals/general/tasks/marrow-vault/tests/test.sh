#!/bin/bash
#
# marrow-vault verifier. EXECUTES the deliverable /app/rtl/sync_fifo.v
# (the agent's Verilog FIFO) by compiling it together with three hidden
# testbenches under /tests/hidden/ and simulating each with vvp, requiring
# its PASS sentinel. Every hidden testbench embeds an independent golden
# behavioral model and compares dout/full/empty/count cycle by cycle, so a
# stub that only satisfies the visible fixture fails. Writes REWARD (0/1)
# to /logs/verifier/reward.txt on EVERY exit path (EXIT trap).
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

log() { echo "marrow-vault verify: $*" >&2; }

RTL=/app/rtl/sync_fifo.v

# ---------------------------------------------------------------------------
# 1. Deliverable present and non-empty.
# ---------------------------------------------------------------------------
if [ ! -f "$RTL" ] || [ ! -s "$RTL" ]; then
  overall=0; msgs="$msgs missing-deliverable:$RTL"
fi

# ---------------------------------------------------------------------------
# 2. Compile + simulate the agent's module against every hidden testbench.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  for tb in /tests/hidden/htb_rand.v /tests/hidden/htb_edge.v /tests/hidden/htb_big.v; do
    name=$(basename "$tb" .v)
    if [ ! -f "$tb" ]; then
      overall=0; msgs="$msgs missing-hidden-tb:$name"
      continue
    fi
    vvp_bin=/tmp/tb3_agate_latch_${name}.vvp
    rm -f "$vvp_bin"

    if ! $TIMEOUT_CMD 60 iverilog -g2005 -o "$vvp_bin" "$tb" "$RTL" 2>/tmp/tb3_compile_${name}.log; then
      overall=0; msgs="$msgs $name:compile-fail"
      tail -6 /tmp/tb3_compile_${name}.log >&2 2>/dev/null || true
      continue
    fi

    if ! $TIMEOUT_CMD 60 vvp "$vvp_bin" >/tmp/tb3_sim_${name}.log 2>&1; then
      overall=0; msgs="$msgs $name:sim-fail"
      tail -6 /tmp/tb3_sim_${name}.log >&2 2>/dev/null || true
      continue
    fi

    if ! grep -q "PASS_HIDDEN_${name}" /tmp/tb3_sim_${name}.log; then
      overall=0; msgs="$msgs $name:no-pass-sentinel"
      tail -12 /tmp/tb3_sim_${name}.log >&2 2>/dev/null || true
      continue
    fi
    if grep -q "HIDDEN_FAIL" /tmp/tb3_sim_${name}.log; then
      overall=0; msgs="$msgs $name:fail-lines-present"
      tail -12 /tmp/tb3_sim_${name}.log >&2 2>/dev/null || true
    fi
  done
fi

if [ "$overall" = "1" ]; then
  log "all hidden cases passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0