#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
rows = []
for line in open('/app/input.txt', encoding='utf-8').read().splitlines():
    line = line.rstrip('\n')
    if not line.strip():
        continue
    name, score = line.split()
    rows.append((name, int(score)))
rows.sort(key=lambda r: r[0])
exp = [f"{n} {s}" for n, s in rows] + [f"TOTAL {sum(s for _, s in rows)}"]
got = open('/app/report.txt', encoding='utf-8').read().splitlines()
assert got == exp
PYEOF
then
    reward=1
fi
echo "$reward" > /logs/verifier/reward.txt