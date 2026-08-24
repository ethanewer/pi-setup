#!/bin/bash
set -euo pipefail
awk -F: '{print $2}' /app/secrets.htpasswd > /app/extracted_hash.txt
printf 'apr1\n' > /app/hash_format.txt
echo "wrote extracted hash and format"