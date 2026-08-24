#!/bin/bash

mkdir -p /logs/verifier

reward=0

if [ -f /app/found/solution.json ]; then
python3 - <<'PY'
import json, subprocess, sys

def S(b): return (7*int(b)+3)&0xFF
def subkey(K,r): return ((K+17*r)&0xFF)^((K>>8)&0xFF)
def enc(K,P):
    L=(P>>8)&0xFF; R=P&0xFF
    for r in range(6):
        f=S(R^subkey(K,r)); L,R=R,(L^f)&0xFF
    return (L<<8)|R
def dec(K,C):
    L=(C>>8)&0xFF; R=C&0xFF
    for r in range(5,-1,-1):
        f=S(L^subkey(K,r)); L,R=(R^f)&0xFF,L
    return (L<<8)|R

def oracle(kind,arg=None):
    cmd=['/app/candle',kind] if arg is None else ['/app/candle',kind,arg]
    out=subprocess.run(cmd,capture_output=True,text=True).stdout.strip()
    return int(out,16)

try:
    sol=json.load(open('/app/found/solution.json'))
    key=int(sol['key'],16)
except Exception:
    sys.exit(1)

# recovered key must reproduce the oracle on several plaintexts
for p in (0x0000,0x0001,0x0080,0x00FF):
    if enc(key,p)!=oracle('enc','%02X'%p):
        sys.exit(1)

# challenge decrypts to the true plaintext under the recovered key
ch=oracle('challenge')
pt=dec(key,ch)
if pt!=0x4F4B:
    sys.exit(1)
if sol['plain']!='%04X'%0x4F4B:
    sys.exit(1)
if sol['plain'].upper()!=('%04X'%pt).upper():
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt
