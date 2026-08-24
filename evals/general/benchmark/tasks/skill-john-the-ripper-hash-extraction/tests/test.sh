#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp_token=$(awk -F: '{print $2}' /app/secrets.htpasswd 2>/dev/null)
if [ -n "$exp_token" ] && [ -f /app/extracted_hash.txt ] && [ -f /app/hash_format.txt ]; then
  got_token=$(python3 -c "import sys;print(open('/app/extracted_hash.txt').read().strip())" 2>/dev/null)
  got_fmt=$(python3 -c "import sys;print(open('/app/hash_format.txt').read().strip().lower())" 2>/dev/null)
  allowed={"apr1","apache_md5","md5crypt-apr1","apache-md5"}
  if [ "$got_token" = "$exp_token" ] && [ -n "$got_fmt" ] && python3 -c "import sys;sys.exit(0 if '$got_fmt' in ['apr1','apache_md5','md5crypt-apr1','apache-md5'] else 1)" 2>/dev/null; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt