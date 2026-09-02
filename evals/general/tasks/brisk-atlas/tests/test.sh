#!/usr/bin/env bash
# brisk-atlas verifier. Runs after the agent (solution) within the built image.
# The agent must deliver /app/fix.sh and /app/audit.txt; the verifier executes
# the deliverable and asserts the hardened end-state, then hidden cases probe
# generalization over dirty/edge starting states.
set -u
REWARD=0
log(){ echo "$*"; }
mkdir -p /logs/verifier

source /tests/lib.sh

# ---- require the deliverables (negative control: pristine image fails here)
if [ ! -f /app/fix.sh ]; then
  log "DELIVERABLE /app/fix.sh missing"
  echo "$REWARD" > /logs/verifier/reward.txt
  exit 0
fi

# ---- execute the deliverable against the /app fixtures (literal path)
bash /app/fix.sh || { log "fix.sh returned nonzero"; echo "$REWARD" > /logs/verifier/reward.txt; exit 0; }
[ -f /app/audit.txt ] || { log "audit.txt not produced"; echo "$REWARD" > /logs/verifier/reward.txt; exit 0; }

# ---- final-state checks
if check_final_state; then
  log "final_state: PASS"
  REWARD=1
else
  log "final_state: FAIL"
  REWARD=0
  echo "$REWARD" > /logs/verifier/reward.txt
  exit 0
fi

# ---- hidden cases (each sets a different dirty/edge state, re-runs fix.sh,
# and must still arrive at the full spec)
for c in /tests/hidden/*.sh; do
  [ -f "$c" ] || continue
  if bash "$c"; then
    log "hidden $(basename "$c"): PASS"
  else
    log "hidden $(basename "$c"): FAIL"
    REWARD=0
    break
  fi
done

echo "$REWARD" > /logs/verifier/reward.txt
exit 0