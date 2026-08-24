#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
from Bio import SeqIO
expected = []
for rec in SeqIO.parse('/app/sequences.fasta', 'fasta'):
    s = ''.join(str(rec.seq))
    total = len(s)
    c = {ch: s.count(ch) for ch in 'ACGT'}
    gc = c['G'] + c['C']
    gc_pct = round(100.0 * gc / total, 2) if total else 0.0
    expected.append({'id': rec.id, 'length': total, 'counts': c, 'gc_pct': gc_pct})
got = json.load(open('/app/summary.json'))
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt