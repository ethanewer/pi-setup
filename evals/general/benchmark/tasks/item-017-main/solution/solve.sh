#!/bin/bash
set -uo pipefail

# 1. extract the outer (unencrypted) vault
mkdir -p /app/vault
7z x -y -o/app/vault /app/vault.7z > /dev/null

# 2. crack the raw MD5 with john against the bundled wordlist
mkdir -p /app/out
john --wordlist=/app/vault/wordlist.txt --format=Raw-MD5 /app/vault/hash.txt > /dev/null 2>&1

# 3. recover the cracked plaintext password from john's election.
pw=""
john --show --format=Raw-MD5 /app/vault/hash.txt 2>/dev/null > /tmp/show.txt
# john --show prints '<hash>:<password>' records; grab the shortest token after the colon
if [ -s /tmp/show.txt ]; then
  # pick the last colon-separated token that looks like a single dictionary word
  pw=$(grep -Eo ':[A-Za-z0-9]+$' /tmp/show.txt | head -1 | tr -d ':')
fi
if [ -z "$pw" ]; then
  pw=$(grep -Eo '(^|:)[A-Za-z0-9_]+$' /tmp/show.txt | tail -1 | tr -d ':')
fi
# last-resort deterministic path: match md5 over the wordlist (mirrors what john would crack)
if [ -z "$pw" ]; then
  hashline=$(cat /app/vault/hash.txt | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
  for w in $(cat /app/vault/wordlist.txt); do
    h=$(printf '%s' "$w" | openssl dgst -md5 2>/dev/null | awk '{print $NF}' | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
    if [ "$h" = "$hashline" ]; then pw="$w"; break; fi
  done
fi

if [ -n "$pw" ]; then
  7z x -y -o/app/out "/app/vault/secret.7z" -p"$pw" >/dev/null 2>&1
  if [ -f /app/out/secret.txt ]; then
    printf '%s' "$(cat /app/out/secret.txt | sed 's/[[:space:]]*$//')" > /app/recovered.txt
  fi
fi

exit 0