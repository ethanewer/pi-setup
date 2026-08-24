#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/primers.json ] && [ -f /app/plasmid.fasta ] && [ -f /app/plan.json ]; then
  if python3 - <<'PYEOF'
import json

def read_dna(path):
    parts = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('>'):
            continue
        parts.append(line)
    return ''.join(parts)

V = read_dna('/app/plasmid.fasta')
plan = json.load(open('/app/plan.json'))
L = len(V)
bs = plan['back_start']; sl = plan['seam_length']
ins = plan['insert']; pr = plan['primer_length']
T = V + V
exp_f = T[L + bs - pr : L + bs]
exp_w = T[bs + sl : bs + sl + pr]
MAP = {'A':'T','T':'A','C':'G','G':'C'}
exp_r = ''.join(MAP[c] for c in reversed(exp_w))
exp_a = V[0:bs] + ins + V[bs+sl:L]

for p in (exp_f, exp_r):
    assert plan['length_range'][0] <= len(p) <= plan['length_range'][1]
    gc = 100.0*(p.count('G')+p.count('C'))/len(p)
    assert plan['gc_range'][0] <= gc <= plan['gc_range'][1]
    a = p.count('A')+p.count('T'); g = p.count('G')+p.count('C')
    tmv = 2*a+4*g
    assert plan['tm_range'][0] <= tmv <= plan['tm_range'][1]

got = json.load(open('/app/primers.json'))
assert got['assembled'] == exp_a, 'assembled mismatch'
assert got['forward'] == exp_f, 'forward mismatch'
assert got['reverse'] == exp_r, 'reverse mismatch'
assert got['valid'] is True
assert got['length_ok'] is True and got['gc_ok'] is True and got['tm_ok'] is True
assert len(exp_a) == L - sl + len(ins)
assert exp_r != exp_f
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt