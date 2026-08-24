#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/plasmid_mutated.fa ] && [ -f /app/primers.fa ] && [ -f /app/validation.txt ]; then
  if python3 - <<'PY'
def parse_fasta(path):
    label = None
    seq_parts = []
    for raw in open(path):
        line = raw.rstrip('\n').rstrip('\r')
        if not line.strip():
            continue
        if line.startswith('>'):
            if label is None:
                label = line[1:].strip()
        else:
            seq_parts.append(line.strip())
    return label, ''.join(seq_parts)

_, S = parse_fasta('/app/plasmid.fa')
p_str, P = open('/app/edit.txt').read().split()
p = int(p_str)
M = S[:p] + P + S[p:]

REV = {'A': 'T', 'T': 'A', 'G': 'C', 'C': 'G'}
def rev(x):
    return ''.join(REV[c] for c in reversed(x))

def preceding(pos, k):
    n = len(S)
    idx = [(pos - 1 - j) % n for j in range(k)]
    return ''.join(S[i] for i in reversed(idx))

F_exp = preceding(p, 10) + P[:10]
win = M[p - 8:p + 12]
R_exp = rev(win)

def gcfrac(x):
    return sum(1 for c in x if c in 'GC') / len(x)

constraints_ok = (18 <= len(F_exp) <= 25 and 18 <= len(R_exp) <= 25 and
                  0.40 <= gcfrac(F_exp) <= 0.60 and 0.40 <= gcfrac(R_exp) <= 0.60)
if not constraints_ok:
    raise SystemExit('expected primers to pass constraints')

_, M_got = parse_fasta('/app/plasmid_mutated.fa')
prim_lines = [l.strip() for l in open('/app/primers.fa').read().splitlines()
              if l.strip() and not l.lstrip().startswith('>')]
if len(prim_lines) != 2:
    raise SystemExit(prim_lines)
F_got, R_got = prim_lines

val = open('/app/validation.txt').read().strip()
if M_got != M:
    raise SystemExit((M_got, M))
if F_got != F_exp:
    raise SystemExit((F_got, F_exp))
if R_got != R_exp:
    raise SystemExit((R_got, R_exp))
if val != 'OK':
    raise SystemExit(val)
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt