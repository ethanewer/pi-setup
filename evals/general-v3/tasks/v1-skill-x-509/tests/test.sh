#!/bin/bash

reward=0
if [ -f /app/cert.pem ]; then
  subj=$(openssl x509 -in /app/cert.pem -noout -subject 2>/tmp/x509.log)
  if [ -n "$subj" ] && echo "$subj" | grep -q "example.com"; then
    if openssl x509 -in /app/cert.pem -noout -checkend 0 >/dev/null 2>&1; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt