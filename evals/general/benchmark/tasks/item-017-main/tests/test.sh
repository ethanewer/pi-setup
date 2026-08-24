#!/bin/bash
# Verifier for item-017-main: the recovered flag must match the secret in the archive.
mkdir -p /logs/verifier

EXPECTED="HARBOR3X-1777-DELTA"
match=0
if [ -f /app/recovered.txt ]; then
  recovered=$(cat /app/recovered.txt | sed 's/[[:space:]]*$//')
  if [ "$recovered" = "$EXPECTED" ]; then
    match=1
  fi
fi

echo "$([ "$match" = "1" ] && echo '1.00' || echo '0.00')" > /logs/verifier/reward.txt