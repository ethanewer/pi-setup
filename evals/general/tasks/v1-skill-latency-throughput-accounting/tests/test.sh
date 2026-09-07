#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/transfers.json ] && [ -f /app/metrics.json ]; then
  if python3 - <<'PYEOF'
import json
recs = json.load(open('/app/transfers.json'))
total_bytes = sum(r['bytes'] for r in recs)
total_dur   = sum(r['duration_sec'] for r in recs)
avg_lat     = total_dur / len(recs)
exp = {"throughput_bps": round(total_bytes / total_dur, 3), "avg_latency_sec": round(avg_lat, 3)}
got = json.load(open('/app/metrics.json'))
for k in exp:
    assert abs(got.get(k, -1) - exp[k]) <= 1e-9, (k, got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt