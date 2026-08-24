#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/cleaned.csv ]; then
  if python3 - <<'PYEOF'
import csv, re
expected = [
    ["id", "user", "status"],
    ["1", "ada", "lead engineer"],
    ["2", "alice", "beta tester"],
    ["3", "linus", "kernel hacker"],
]
def norm(rows):
    out = []
    for r in rows:
        c = [x.strip() for x in r]
        c = [x.lower() if x not in ('id', '1', '2', '3') else x for x in c]
        c = [re.sub(r'\s+', ' ', x) for x in c]
        out.append(c)
    return out
with open('/app/cleaned.csv', newline='') as f:
    got = [list(r) for r in csv.reader(f)]
assert norm(got) == norm(expected), (norm(got), norm(expected))
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt