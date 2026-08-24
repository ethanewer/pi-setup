#!/bin/bash
set -euo pipefail
openssl pkeyutl -encrypt -pubin -inkey /app/public.pem \
    -in /app/message.txt -out /app/message.enc \
    -pkeyopt rsa_padding_mode:oaep
echo "encrypted message.txt -> message.enc"