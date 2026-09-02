#!/bin/bash
#
# prism-hearth verifier.
#   * requires the authored deliverables /app/infer.py (runnable) plus the
#     /app/loss.txt and /app/batch_plan.json output files
#   * EXECUTES /app/infer.py on the visible scenario (/app/job.json) and on
#     every hidden scenario under /tests/hidden
#   * checks outputs against golden references via tests/verify.py: loss,
#     AFAB microbatch plan + budgets, policy/WDL heads, microbatched gradient
#     accumulation, and the local causal-LM + tokenizer load
#   * confirms the immutable weight artifacts are byte-for-byte identical
# Rewards 1 iff all checks pass.
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "FIELD: $*"; ok=0; }

# ---- A. deliverables present ----
[ -f /app/infer.py ]            || fail "missing /app/infer.py"
[ -x /app/infer.py ]            || fail "/app/infer.py not executable"
[ -f /app/loss.txt ]            || fail "missing /app/loss.txt"
[ -f /app/batch_plan.json ]     || fail "missing /app/batch_plan.json"

# ---- B. immutable artifacts byte-for-byte identical ----
[ -f /app/weights/hearth_net.pt ] || fail "hearth_net.pt missing"
cmp -s /app/weights/hearth_net.pt /tests/_pristine/hearth_net.pt \
  || fail "hearth_net.pt not byte-for-byte identical to pristine"
cmp -s /app/models/verlok_lm/model.safetensors /tests/_pristine/model.safetensors \
  || fail "model.safetensors not byte-for-byte identical to pristine"

# ---- single-scenario runner ----
run_case() {
  local job out exp
  job=$1; out=$2; exp=$3
  rm -rf "$out" && mkdir -p "$out"
  if python3 /app/infer.py "$job" "$out" >/dev/null 2>&1; then
    :
  else
    fail "infer.py failed on $(basename "$job")"
    return
  fi
  python3 /tests/verify.py "$job" "$out" "$exp" \
    || fail "verify failed on $(basename "$job")"
}

# ---- visible ----
run_case /app/job.json /tmp/out_vis /tests/expected

# ---- hidden scenarios ----
if [ -d /tests/hidden ]; then
  for job in /tests/hidden/*/job.json; do
    [ -e "$job" ] || continue
    casedir=$(dirname "$job")
    [ -d "$casedir/expected" ] || { fail "hidden $(basename "$casedir") has no expected"; continue; }
    run_case "$job" "/tmp/out_$(basename "$casedir")" "$casedir/expected"
  done
fi

# ---- reward ----
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$ok" > /logs/verifier/reward.txt
echo "reward=$reward (ok=$ok)" >&2
exit 0