#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/predictions.json ]; then
  if python3 - <<'PYEOF'
import json

# Recompute expected predictions from the fixed training/test files.
positive = set()
negative = set()
with open("/app/training.txt") as f:
    for line in f:
        line = line.strip()
        if not line or "\t" not in line:
            continue
        word, label = line.split("\t")
        (positive if label == "pos" else negative).add(word)

with open("/app/test.txt") as f:
    test_lines = [ln.strip() for ln in f if ln.strip()]

expected = []
for line in test_lines:
    tokens = line.split()
    if any(w in positive for w in tokens):
        expected.append("pos")
    elif any(w in negative for w in tokens):
        expected.append("neg")
    else:
        expected.append("pos")

with open("/app/predictions.json") as f:
    got = json.load(f)

assert isinstance(got, list) and len(got) == len(expected), (got, expected)
assert [str(x).lower() for x in got] == expected, (got, expected)
print("OK", expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt