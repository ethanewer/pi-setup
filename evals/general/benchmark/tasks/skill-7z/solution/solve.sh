#!/bin/bash
set -euo pipefail
rm -rf /app/extract
mkdir -p /app/extract
7z e -o/app/extract /app/archive.7z
# find the extracted member (the only non-directory entry)
found=""
for f in /app/extract/*; do
  if [ -f "$f" ]; then found="$f"; break; fi
done
if [ -z "$found" ]; then
  echo "no file extracted"; exit 1
fi
sed -e 's/[[:space:]]*$//' "$found" > /app/secret_out.txt
echo "wrote /app/secret_out.txt"