#!/bin/bash
# Verifier for skill-rsa-2048. Decrypts the agent's message.enc with the
# private key and compares to the plaintext in /app/message.txt.
mkdir -p /logs/verifier

reward=0
if [ -f /app/message.enc ] && [ -f /app/private.pem ]; then
  rm -f /tmp/dec.out /tmp/dec.err
  openssl pkeyutl -decrypt -inkey /app/private.pem \
      -in /app/message.enc -out /tmp/dec.out -pkeyopt rsa_padding_mode:oaep \
      >/dev/null 2>/tmp/dec.err
  if [ -s /tmp/dec.out ]; then
    expected=$(cat /app/message.txt)
    decrypted=$(cat /tmp/dec.out)
    if [ "$decrypted" = "$expected" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt