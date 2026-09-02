#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/stats.json ]; then
  if python3 - <<'PYEOF'
import json
records = []
cur = None
parts = []
for line in open('/app/data.fasta'):
    line = line.rstrip('\n')
    if line.startswith('>'):
        if cur is not None:
            records.append((cur, ''.join(parts)))
        cur = line[1:]
        parts = []
    elif cur is not None and line.strip():
        parts.append(line.strip())
if cur is not None:
    records.append((cur, ''.join(parts)))
total = sum(len(s) for _, s in records)
longest_id, longest_len = records[0][0], len(records[0][1])
for rid, s in records:
    if len(s) > longest_len:
        longest_id, longest_len = rid, len(s)
expected = {'num_records': len(records), 'total_length': total,
            'longest_id': longest_id, 'longest_len': longest_len}
got = json.load(open('/app/stats.json'))
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt