#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/bench.json ]; then
  if python3 - <<'PYEOF'
import json, sys, time
sys.path.insert(0, '/app')
from candidates import impl_a, impl_b
n = 5000000
reps = 10
def bench(fn):
    best = float('inf')
    for _ in range(reps):
        t0 = time.perf_counter()
        fn(n)
        dt = time.perf_counter() - t0
        best = min(best, dt)
    return best
ta = bench(impl_a); tb = bench(impl_b)
winner = 'A' if ta > tb else ('B' if tb > ta else 'A')
got = json.load(open('/app/bench.json'))
assert got.get('winner_slower') in ('A', 'B')
assert got.get('reps') == reps
assert float(got.get('time_a_sec', -1)) >= 0 and float(got.get('time_b_sec', -1)) >= 0
assert got['winner_slower'] == winner, (got['winner_slower'], winner)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt