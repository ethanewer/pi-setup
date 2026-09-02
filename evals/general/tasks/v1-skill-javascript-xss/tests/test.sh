#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json, re
d = json.load(open('/app/answer.json'))
def norm(s):
    return re.sub(r'[^a-z0-9]', '', str(s).lower())
vuln = norm(d.get('vulnerable', ''))
issue = " " + norm(d.get('issue', '')) + " "
fix = " " + norm(d.get('fix', '')) + " "
if vuln != 'yes':
    raise SystemExit('vulnerable not yes')
has_input = ('input' in issue) or ('userinput' in issue)
has_unsafe = ('unescaped' in issue) or ('untrusted' in issue) or ('raw' in issue) or ('directly' in issue)
if not (has_input and has_unsafe):
    raise SystemExit('issue not recognized')
ok_fix = (('escape' in fix) or ('encode' in fix) or ('sanitiz' in fix) or ('neutraliz' in fix))
if not ok_fix:
    raise SystemExit('fix not recognized')
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt