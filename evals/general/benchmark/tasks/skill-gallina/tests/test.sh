#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/gallina.v ]; then
  if python3 - <<'EOF'
import re
with open('/app/gallina.v') as f:
    text = f.read()

body = re.sub(r'\(\*.*?\*\)', '', text, flags=re.S)

bad = []
if not re.search(r'Fixpoint\s+double\s*\(\s*n\s*:\s*nat\s*\)\s*:\s*nat\s*:=', body):
    bad.append('signature')
if 'match n with' not in body:
    bad.append('match')
if not re.search(r'\|?\s*0\s*=>\s*0', body):
    bad.append('base')
if not re.search(r'S\s*\(\s*S\s*\(\s*double\b', body):
    bad.append('recursive')
if not re.search(r'end\.\s*$', text.strip()):
    bad.append('end')
if body.count('(') != body.count(')'):
    bad.append('parens')

if bad:
    raise SystemExit((bad, text))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt