#!/bin/bash
# Verifier for item-030-main. Objective checks only.
# Reward = A(0.25 recovery) + B(0.25 placeholder) + C(0.25 no leak) + D(0.25 refs/clean).
mkdir -p /logs/verifier

AWS_ID="AKIAEXAMPLEKEY000001"
AWS_SECRET="EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GH_PAT="ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"

if ! cd /app/repo 2>/dev/null; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

A=0 B=0 C=0 D=0

# A: a recovery copy of the original secrets exists outside the repo and
#    contains every one of the original credential strings.
if [ -f /app/recovery/original-secrets.txt ]; then
  s=$(tr -d '\r' < /app/recovery/original-secrets.txt)
  if [[ "$s" == *"$AWS_ID"* && "$s" == *"$AWS_SECRET"* && "$s" == *"$GH_PAT"* ]]; then
    A=1
  fi
fi

# B: placeholder substitution happened in reachable history AND the worktree.
if git log -p --all 2>/dev/null | grep -qaF '<REDACTED>'; then
  if grep -qaF '<REDACTED>' config.py 2>/dev/null; then
    B=1
  fi
fi

# C: no leaked credential bytes anywhere: every object (reachable from ANY
#    ref - including leftover backup refs - plus unreachable/reflog-pinned ones)
#    drained through git cat-file, plus all worktree files.
leak=0
{ git rev-list --objects --all 2>/dev/null | awk '{print $1}'; \
  git fsck --no-reflogs --unreachable 2>/dev/null | awk '{print $3}'; } | sort -u | while read -r id; do
  if git cat-file -p "$id" 2>/dev/null | grep -aqF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT"; then
    echo "LEAK:$id"
  fi
  done > /tmp/leakscan.txt
if [ -s /tmp/leakscan.txt ]; then leak=1; fi
if [ "$leak" = 0 ]; then
  if grep -rqaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" . --exclude-dir=.git 2>/dev/null; then
    leak=1
  fi
fi
if [ "$leak" = 0 ]; then C=1; fi

# D: all refs intact, commit count preserved, working tree clean, fsck healthy,
#    and ORIG_HEAD removed or pointing at the (clean) rewritten HEAD.
D=1
git rev-parse --verify -q main  >/dev/null 2>&1 || D=0
git rev-parse --verify -q staging >/dev/null 2>&1 || D=0
git rev-parse --verify -q refs/tags/v1.0 >/dev/null 2>&1 || D=0
[ -z "$(git rev-list --all --count 2>/dev/null)" ] && D=0
[ "$(git rev-list --all --count 2>/dev/null)" = "4" ] || D=0
[ -z "$(git status --porcelain 2>/dev/null)" ] || D=0
if git fsck --full 2>&1 | grep -E '^missing|^broken' >/dev/null; then D=0; fi
if [ -f .git/ORIG_HEAD ] && [ -s .git/ORIG_HEAD ]; then
  oh=$(cat .git/ORIG_HEAD)
  [ "$oh" = "$(git rev-parse HEAD)" ] || [ -z "$(git cat-file -p "$oh" 2>/dev/null | grep -aE 'AKIA|ghp_')" ] || D=0
  if git cat-file -e "$oh" 2>/dev/null; then
    if git cat-file -p "$oh" 2>/dev/null | grep -aqE 'AKIA|ghp_'; then D=0; fi
  fi
fi

reward=$(awk "BEGIN{print $A*0.25+$B*0.25+$C*0.25+$D*0.25}")
echo "$reward" > /logs/verifier/reward.txt