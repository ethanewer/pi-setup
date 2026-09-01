#!/bin/bash
set -euo pipefail

cat > /app/design_primers.py <<'PYEOF'
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
forward = T[L + bs - pr : L + bs]
window = T[bs + sl : bs + sl + pr]
MAP = {'A':'T','T':'A','C':'G','G':'C'}
reverse = ''.join(MAP[c] for c in reversed(window))
assembled = V[0:bs] + ins + V[bs+sl:L]

def gc_pct(s):
    return 100.0 * (s.count('G') + s.count('C')) / len(s)

def tm(s):
    a = s.count('A') + s.count('T')
    g = s.count('G') + s.count('C')
    return 2*a + 4*g

def check(s):
    lo, hi = plan['length_range']
    gc_lo, gc_hi = plan['gc_range']
    tm_lo, tm_hi = plan['tm_range']
    len_ok = lo <= len(s) <= hi
    gc_ok = gc_lo <= gc_pct(s) <= gc_hi
    tmv = tm(s)
    tm_ok = tm_lo <= tmv <= tm_hi
    return len_ok, gc_ok, tm_ok

out = {"assembled": assembled, "forward": forward, "reverse": reverse,
       "length_ok": True, "gc_ok": True, "tm_ok": True, "valid": True}
for name, p in (("forward", forward), ("reverse", reverse)):
    len_ok, gc_ok, tm_ok = check(p)
    for flag, ok in (("length_ok", len_ok), ("gc_ok", gc_ok), ("tm_ok", tm_ok)):
        if not ok:
            out[flag] = False
            out["valid"] = False
            out[name + "_" + flag] = ok

with open('/app/primers.json', 'w') as f:
    json.dump(out, f, indent=2)
print("wrote /app/primers.json")
PYEOF

python3 /app/design_primers.py