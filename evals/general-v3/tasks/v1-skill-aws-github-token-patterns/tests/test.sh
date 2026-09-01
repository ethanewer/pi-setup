#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/tokens.txt ] && [ -f /app/answer.json ]; then
  python3 - <<'EOF'
import json, re
tokens=[l.strip() for l in open('/app/tokens.txt') if l.strip()]
def classify(tok):
    if re.fullmatch(r'AKIA[0-9A-Z]{16}', tok): return 'aws_access'
    if re.fullmatch(r'[A-Za-z0-9/+=]{40}', tok): return 'aws_secret'
    if re.fullmatch(r'gh[pousr]_[A-Za-z0-9_]{24,}', tok): return 'github'
    return 'other'
exp=[{"value": t, "type": classify(t)} for t in tokens]
got=json.load(open('/app/answer.json'))
if got != exp:
    print("expected=%r  got=%r" % (exp, got))
    exit(1)
exit(0)
EOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt