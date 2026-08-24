#!/bin/bash
# Verifier for item-029-main: objective decode check against the actual file.
mkdir -p /logs/verifier
reward=0

if [ -f /app/job.gcode ] && [ -f /app/decoded.txt ]; then
  expected=$(python3 - <<'EOF'
import re
ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
out = []
with open("/app/job.gcode") as f:
    for line in f:
        if not re.match(r"\s*G1\b", line):
            continue
        m = re.search(r"\bE([0-9]+(?:\.[0-9]*)?)", line)
        if m:
            out.append(ABC[int(float(m.group(1)))])
print("".join(out), end="")
EOF
)
  got=$(tr -d '\r\n' < /app/decoded.txt)
  if [ -n "$expected" ] && [ "$got" = "$expected" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt