#!/bin/bash
set -euo pipefail

mkdir -p /app/certs
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out /app/certs/server.key
openssl req -new -x509 -key /app/certs/server.key -sha256 -days 365 \
  -subj "/CN=server.example.com" \
  -addext "subjectAltName = DNS:server.example.com, DNS:api.example.com, DNS:admin.example.com" \
  -out /app/certs/server.pem

# Inspect the generated artifacts (do not just trust exit status).
openssl pkey -in /app/certs/server.key -noout -check
openssl x509 -in /app/certs/server.pem -noout -subject -startdate -notdate 2>/dev/null || openssl x509 -in /app/certs/server.pem -noout -subject -startdate -enddate
openssl x509 -in /app/certs/server.pem -noout -text | grep -E "Signature Algorithm|Public-Key|Subject Alternative Name|DNS:"
openssl pkey -in /app/certs/server.key -pubout -outform DER | openssl dgst -sha256 > /tmp/keyhash.txt
openssl x509 -in /app/certs/server.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 > /tmp/carthash.txt
echo "match: $(cmp -s /tmp/keyhash.txt /tmp/carthash.txt && echo yes || echo no)"