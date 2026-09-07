#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0

if [ -f /app/out/cert_info.json ]; then
python3 - <<'PY'
import json, subprocess, sys

def o():
    return subprocess.run(
        ['openssl','x509','-in','/app/cert.pem','-noout','-subject','-dates'],
        capture_output=True, text=True).stdout.strip()

info = {}
for line in o().splitlines():
    line = line.strip()
    if line.startswith('subject='):
        info['subject'] = line[len('subject='):].strip()
    elif line.startswith('notBefore='):
        info['not_before'] = line[len('notBefore='):].strip()
    elif line.startswith('notAfter='):
        info['not_after'] = line[len('notAfter='):].strip()

import re
m = re.search(r'CN\s*=\s*([^/,]+)', info.get('subject', ''))
cn = m.group(1).strip() if m else None

try:
    d = json.load(open('/app/out/cert_info.json'))
except Exception:
    sys.exit(1)

if d.get('subject','').strip() != info['subject']:
    sys.exit(1)
if (d.get('cn') or '').strip() != (cn or ''):
    sys.exit(1)
if d.get('not_before','').strip() != info['not_before']:
    sys.exit(1)
if d.get('not_after','').strip() != info['not_after']:
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt
