#!/bin/bash
set -euo pipefail

cat > /app/fasta_stats.py <<'PYEOF'
import json

records = []
cur_id = None
seq_parts = []
with open('/app/data.fasta') as f:
    for line in f:
        line = line.rstrip('\n')
        if line.startswith('>'):
            if cur_id is not None:
                records.append((cur_id, ''.join(seq_parts)))
            cur_id = line[1:]
            seq_parts = []
        elif cur_id is not None:
            if line.strip():
                seq_parts.append(line.strip())
if cur_id is not None:
    records.append((cur_id, ''.join(seq_parts)))

num = len(records)
total = sum(len(s) for _, s in records)
longest_id, longest_len = records[0][0], len(records[0][1])
for rid, seq in records:
    if len(seq) > longest_len:
        longest_id, longest_len = rid, len(seq)

out = {'num_records': num, 'total_length': total,
       'longest_id': longest_id, 'longest_len': longest_len}
with open('/app/stats.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /app/fasta_stats.py