#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/primers.txt ]; then
  if python3 - <<'PYEOF'
import sys
seq = open('/app/sequence.txt').read().strip()
lines = open('/app/primers.txt').read().splitlines()
F = None; R = None
for ln in lines:
    if ln.startswith('F: '):
        F = ln[3:].strip()
    elif ln.startswith('R: '):
        R = ln[3:].strip()
assert F and R, 'missing primer lines'
def rc(s):
    return s.translate(str.maketrans('ACGT','TGCA'))[::-1]
def gc(s):
    return 100.0*(s.count('G')+s.count('C'))/len(s)
# conditions
assert 18 <= len(F) <= 25 and 18 <= len(R) <= 25
assert 40.0 <= gc(F) <= 60.0 and 40.0 <= gc(R) <= 60.0
fpos = seq.find(F)
assert fpos != -1, 'F not a substring'
rcR = rc(R)
rpos = seq.find(rcR)
assert rpos != -1, 'rc(R) not a substring'
f_end = fpos + len(F)
r_end = rpos + len(R)
assert f_end <= rpos or r_end <= fpos, 'primers overlap'
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt