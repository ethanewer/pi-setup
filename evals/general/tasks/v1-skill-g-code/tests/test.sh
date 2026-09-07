#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0
if [ -f /app/final_pos.json ]; then
  if python3 - <<'EOF'
import re, json

x = y = 0.0
with open('/app/move.gcode') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        line = re.sub(r';.*', '', line)
        m = re.match(r'G\d+\s+(.*)$', line)
        if not m:
            continue
        xm = re.search(r'X([-+0-9.]+)', m.group(1))
        ym = re.search(r'Y([-+0-9.]+)', m.group(1))
        if xm:
            x = float(xm.group(1))
        if ym:
            y = float(ym.group(1))

expected = {"x": round(x, 3), "y": round(y, 3)}
out = json.load(open('/app/final_pos.json'))
assert out == expected, (out, expected)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt