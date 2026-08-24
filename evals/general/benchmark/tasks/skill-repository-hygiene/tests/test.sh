#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -d "$APP/repo" ] && [ -f "$APP/repo/.gitignore" ] && [ -d "$APP/repo/.git" ]; then
  ok=1
  content=$(cat "$APP/repo/.gitignore")
  for pat in "*.log" "*.tmp" "cache/" "__pycache__/"; do
    if ! printf '%s\n' "$content" | grep -Fq "$pat"; then ok=0; fi
  done
  cd "$APP/repo" || exit 1
  if git ls-files | grep -Eq '(\.log$|\.tmp$|^cache/|__pycache__/)'; then ok=0; fi
  if [ -n "$(git status --porcelain)" ]; then ok=0; fi
  msg=$(git log -1 --format=%s 2>/dev/null)
  if [ "$msg" != "hygiene" ]; then ok=0; fi
  if [ "$ok" = "1" ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt