#!/bin/bash
# Verifier for skill-smtp. Parses the raw message and checks headers + body.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import sys
from email import policy
from email.parser import BytesParser

try:
    with open("/app/message.eml", "rb") as f:
        data = f.read()
except Exception:
    print("0"); sys.exit(0)

msg = BytesParser(policy=policy.default).parsebytes(data)
try:
    frm = str(msg["From"]).strip()
    to = str(msg["To"]).strip()
    subj = str(msg["Subject"]).strip()
except Exception:
    sys.exit(0)
body = msg.get_content()
body = body.strip() if body is not None else ""

if (frm == "sender@example.com"
        and to == "recipient@example.com"
        and subj == "Harbor SMTP Test"
        and body == "Hello from the SMTP test client!"):
    print("1")
else:
    print("0")
sys.exit(0)
PY
)
if [ -z "$reward" ]; then reward="0"; fi
echo "$reward" > /logs/verifier/reward.txt