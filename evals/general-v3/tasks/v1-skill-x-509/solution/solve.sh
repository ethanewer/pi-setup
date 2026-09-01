#!/bin/bash
set -euo pipefail

openssl req -x509 -newkey rsa:2048 -keyout /app/key.pem -out /app/cert.pem \
  -days 365 -nodes -subj "/CN=example.com" -addext "basicConstraints=critical,CA:FALSE"