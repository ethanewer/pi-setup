#!/bin/bash
set -euo pipefail

cat > /app/build_mail.py <<'PY'
from email.message import EmailMessage

msg = EmailMessage()
msg["From"] = "sender@example.com"
msg["To"] = "recipient@example.com"
msg["Subject"] = "Harbor SMTP Test"
msg.set_content("Hello from the SMTP test client!")

with open("/app/message.eml", "wb") as f:
    f.write(msg.as_bytes())
PY

python3 /app/build_mail.py
echo "wrote /app/message.eml"