#!/bin/bash
# Oracle: recover the deleted-branch secret.txt content from dangling commits
# (via reflog and fsck --unreachable) and write it to /app/recovered.txt.
set -euo pipefail
cd /app/repo
content=""
# 1) collect candidate dangling commit ids
ids=$(git reflog --all 2>/dev/null | awk '{print $1}')
if git fsck --unreachable 2>/dev/null | grep -q '^unreachable commit '; then
  for tok in $(git fsck --unreachable 2>/dev/null | awk '/^unreachable commit/{print $3}'); do
    ids="$ids $tok"
  done
fi
for id in $(echo "$ids" | tr ' ' '\n' | sort -u); do
  [ -z "$id" ] && continue
  if git cat-file -e "$id^{commit}" 2>/dev/null; then
    c=$(git show "$id:secret.txt" 2>/dev/null)
    if [ -n "$c" ]; then
      content="$c"
      break
    fi
  fi
done
echo "$content" > /app/recovered.txt