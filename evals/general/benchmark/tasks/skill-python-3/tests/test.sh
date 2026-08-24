#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/report.txt ]; then
  if python3 - <<'PYEOF'
records = []
with open('/app/records.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        name, value = line.split()
        records.append((name, int(value)))

mean = sum(v for _, v in records) / len(records)
expected_lines = [f'{n}={v}' for n, v in records] + [f'mean={mean:.2f}']
expected = '\n'.join(expected_lines) + '\n'

got = open('/app/report.txt').read()
got_norm = got.replace('\r\n', '\n')
assert got_norm == expected, (got_norm, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt