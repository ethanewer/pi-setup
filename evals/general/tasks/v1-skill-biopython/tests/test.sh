#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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