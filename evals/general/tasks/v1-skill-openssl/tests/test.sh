#!/bin/bash
# Verifier for skill-openssl.
# Recompute the SHA-256 fingerprint of the agent's cert and compare with fingerprint.txt.
mkdir -p /logs/verifier
reward=0

if [ -f /app/certs/cert.pem ] && [ -f /app/fingerprint.txt ]; then
  expected=$(openssl x509 -in /app/certs/cert.pem -noout -fingerprint -sha256 \
    | sed 's/.*=//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr 'A-F' 'a-f')
  got=$(cat /app/fingerprint.txt | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\n' | tr 'A-F' 'a-f')
  # Also confirm the cert actually has CN=internal.host.
  subj=$(openssl x509 -in /app/certs/cert.pem -noout -subject 2>/dev/null)
  if [ -n "$expected" ] && [ "$got" = "$expected" ] && echo "$subj" | grep -q "internal.host"; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0