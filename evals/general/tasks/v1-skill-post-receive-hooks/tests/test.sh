#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0

bare_ok=0
if [ -d "$APP/repo.git" ]; then
  rv=$(git --git-dir="$APP/repo.git" rev-parse --is-bare-repository 2>/dev/null | tr -d ' \n')
  if [ "$rv" = "true" ]; then
    bare_ok=1
  fi
fi

if [ "$bare_ok" = "1" ] && [ -f "$APP/repo.git/hooks/post-receive" ] && [ -x "$APP/repo.git/hooks/post-receive" ]; then
  rm -f "$APP/hook.log"
  rm -rf /tmp/pushsrc
  mkdir -p /tmp/pushsrc
  git init -q /tmp/pushsrc
  git -C /tmp/pushsrc config user.email "agent@example.com"
  git -C /tmp/pushsrc config user.name "agent"
  echo "test content" > /tmp/pushsrc/f
  git -C /tmp/pushsrc add f
  git -C /tmp/pushsrc commit -q -m "test commit"
  git -C /tmp/pushsrc remote add origin "$APP/repo.git" 2>/dev/null || git -C /tmp/pushsrc remote set-url origin "$APP/repo.git"
  # force-push: the agent may already have pushed test commits to master,
  # which would otherwise reject this push as non-fast-forward; the
  # post-receive hook fires identically for a forced update.
  push_out=$(git -C /tmp/pushsrc push -f origin HEAD 2>&1)
  push_rc=$?
  echo "push rc=$push_rc out=$push_out"
  sleep 1
  echo "hook.log:"; cat "$APP/hook.log" 2>/dev/null || echo "(missing)"
  if [ -f "$APP/hook.log" ]; then
    if grep -q 'push_received' "$APP/hook.log" && grep -qE 'refs/heads/[A-Za-z0-9_.-]+' "$APP/hook.log"; then
      reward=1
    fi
  fi
fi
echo "bare_ok=$bare_ok hook_exists=$(test -f "$APP/repo.git/hooks/post-receive" && echo 1 || echo 0)"
printf '%s' "$reward" > /logs/verifier/reward.txt