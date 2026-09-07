#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/mteb.json ]; then
  if python3 - <<'PYEOF'
import csv, json
rows = []
with open('/app/leaderboard.csv') as f:
    for r in csv.DictReader(f):
        avg = round((float(r['task_a']) + float(r['task_b']) + float(r['task_c'])) / 3.0, 2)
        rows.append((r['model'], avg))
rows.sort(key=lambda x: x[1], reverse=True)
exp = {"top_model": rows[0][0], "top_score": rows[0][1],
       "ranking": [[name, avg] for name, avg in rows]}
got = json.load(open('/app/mteb.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt