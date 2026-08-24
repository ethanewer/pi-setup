#!/bin/bash
set -uo pipefail
cd /app/repo
content=""
for id in $(git reflog --all 2>/dev/null | awk '{print $1}' | sort -u); do
  if git cat-file -e "${id}^{commit}" 2>/dev/null; then
    v=$(git show "${id}:secret.txt" 2>/dev/null || true)
    if [ -n "$v" ]; then
      content="$v"
      break
    fi
  fi
done
printf '%s' "$content" > /app/recovered.txt
[ -n "$content" ] || { echo "no secret found" >&2; exit 1; }