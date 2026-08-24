#!/bin/bash
# Verifier for item-012-main: compare briefcase.py output to an independent reference.
mkdir -p /logs/verifier

REWARD=0
if [ ! -f /app/briefcase.py ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

cp /tests/test_input.txt /app/input.txt
python3 /app/briefcase.py

if [ ! -f /app/output.txt ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'EOF'
# Independent reference: recompute expected output from /tests/test_input.txt
# using the printed BRIEFCASE REDUCE semantics (own calculation, not the agent's).
def reduce_line(line):
    acc = 0
    for ch in line:
        acc += ord(ch) - ord('a') + 1
    while acc >= 10:
        n = acc
        acc = 0
        while n > 0:
            acc += n % 10
            n //= 10
    return chr(48 + acc)

with open("/tests/test_input.txt", "rb") as f:
    raw = f.read()
text = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n").decode("utf-8")
out = []
for ln in text.split("\n"):
    if ln == "" or not any('a' <= c <= 'z' for c in ln):
        continue
    out.append(reduce_line(ln))
expected = ("\n".join(out) + "\n").encode("utf-8")

with open("/app/output.txt", "rb") as f:
    got = f.read()
norm = lambda b: b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
reward = 1 if norm(expected) == norm(got) else 0
open("/logs/verifier/reward.txt", "w").write(str(reward))
EOF