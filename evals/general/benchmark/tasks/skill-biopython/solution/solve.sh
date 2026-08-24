#!/bin/bash
set -euo pipefail
cat > /app/analyze.py <<'PYEOF'
import json
from Bio import SeqIO
out = []
for rec in SeqIO.parse('/app/sequences.fasta', 'fasta'):
    s = ''.join(str(rec.seq))
    total = len(s)
    c = {ch: s.count(ch) for ch in 'ACGT'}
    gc = c['G'] + c['C']
    gc_pct = round(100.0 * gc / total, 2) if total else 0.0
    out.append({'id': rec.id, 'length': total, 'counts': c, 'gc_pct': gc_pct})
json.dump(out, open('/app/summary.json', 'w'), indent=2)
PYEOF
python3 /app/analyze.py
