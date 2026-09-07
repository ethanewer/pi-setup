#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0

if [ -f /app/report/secret.json ]; then
python3 - <<'PY'
import json, sys, os

try:
    d = json.load(open('/app/report/secret.json'))
except Exception:
    sys.exit(1)

if d.get('file') != 'repo/config/secrets.env':
    sys.exit(1)
if d.get('key') != 'STRIPE_LIVE_KEY':
    sys.exit(1)
if d.get('secret') != 'token_EXAMPLEKEY_EXAMPLEKEY_EXAMPLE':
    sys.exit(1)

# ground truth check straight from the repo files
txt = open('/app/repo/config/secrets.env').read()
if 'token_EXAMPLEKEY_EXAMPLEKEY_EXAMPLE' not in txt:
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt