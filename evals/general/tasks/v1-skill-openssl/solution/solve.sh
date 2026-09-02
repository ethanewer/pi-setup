#!/bin/bash
# Oracle solution for skill-openssl.
set -euo pipefail

mkdir -p /app/certs
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /app/certs/key.pem -out /app/certs/cert.pem \
  -days 365 -subj "/CN=internal.host"

openssl x509 -in /app/certs/cert.pem -noout -fingerprint -sha256 \
  | sed 's/.*=//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' \
  | tr 'A-F' 'a-f' > /app/fingerprint.txt