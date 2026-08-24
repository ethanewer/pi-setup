#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/key.txt ] && [ -f /app/recovered.txt ]; then
  if python3 - <<'PYEOF'
import re, sys, subprocess, random

def S(y): return (y*7+3)&0xFF
def ROL(x,n): return ((x<<n)|(x>>(8-n)))&0xFF

k = open('/app/key.txt','r').read().strip().lower()
if not re.fullmatch(r'[0-9a-f]{8}', k):
    raise SystemExit('bad key format')
key = int(k, 16)
K0 = (key>>24)&0xFF; K1=(key>>16)&0xFF; K2=(key>>8)&0xFF; K3=key&0xFF

def enc_key(p):
    h=(p>>8)&0xFF; l=p&0xFF
    a=S(S(ROL(h,1)^K0)^K1)
    b=S(S(ROL(l,2)^K2)^K3)
    return 0xFFFF & ((a<<8)|(a^b))

def oracle(p):
    r=subprocess.run(['/app/cullet','enc','%04X'%p],capture_output=True,text=True)
    return int(r.stdout.strip(),16)

random.seed(0xC0FFEE)
for p in [random.randrange(65536) for _ in range(64)]:
    if enc_key(p) != oracle(p):
        raise SystemExit('key mismatch')

ct=int(subprocess.run(['/app/cullet','challenge'],capture_output=True,text=True).stdout.strip(),16)
found=None
for p in range(65536):
    if enc_key(p)==ct:
        found=p; break
if found is None:
    raise SystemExit('no plaintext')
got=open('/app/recovered.txt','r').read().strip().upper()
if got != '%04X'%found:
    raise SystemExit('recovered mismatch')
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt