#!/bin/bash
# Verifier for item-030-hard. Objective checks only.
# Reward = A(0.2 recovery) + B(0.2 placeholder, content+messages)
#        + C(0.2 no credential bytes anywhere) + D(0.2 refs/count/orig_head)
#        + E(0.2 hygiene: clean status, no stray token files, fsck healthy).
mkdir -p /logs/verifier

AWS_ID="AKIAEXAMPLEKEY000001"
AWS_SECRET="EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GH_PAT="ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"
GH_FINE="github_pat_EXAMPLE_EXAMPLE_EXAMPLE"

if ! cd /app/repo 2>/dev/null; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

A=0 B=0 C=0 D=0 E=0

# A: recovery copy contains ALL FOUR original credential strings.
if [ -f /app/recovery/original-secrets.txt ]; then
  s=$(tr -d '\r' < /app/recovery/original-secrets.txt)
  if [[ "$s" == *"$AWS_ID"* && "$s" == *"$AWS_SECRET"* && "$s" == *"$GH_PAT"* && "$s" == *"$GH_FINE"* ]]; then
    A=1
  fi
fi

# B: placeholders present in reachable history file content AND commit messages.
msg_ok=0
if git log --all --format='%B' 2>/dev/null | grep -qaF '<REDACTED>'; then
  msg_ok=1
fi
cont_ok=0
if git log -p --all 2>/dev/null | grep -qaF '<REDACTED>'; then
  cont_ok=1
fi
[ "$msg_ok" = 1 ] && [ "$cont_ok" = 1 ] && B=1

# C: no credential bytes in ANY object (reachable + unreachable, incl.
#    reflog-pinned and packed ones) drained via git cat-file.
leak=0
{ git rev-list --objects --all 2>/dev/null | awk '{print $1}'; \
  git fsck --no-reflogs --unreachable 2>/dev/null | awk '{print $3}'; } | sort -u | while read -r id; do
  if git cat-file -p "$id" 2>/dev/null | grep -aqF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE"; then
    echo "LEAK:$id"
  fi
  done > /tmp/leakscan.txt
if [ -s /tmp/leakscan.txt ]; then leak=1; fi
if [ "$leak" = 0 ]; then
  if grep -rqaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE" . --exclude-dir=.git 2>/dev/null; then
    leak=1
  fi
fi
if [ "$leak" = 0 ]; then C=1; fi

# D: every ref survived the rewrite, commit count preserved, fsck healthy,
#    ORIG_HEAD gone or pointing at a clean commit.
D=1
git rev-parse --verify -q main         >/dev/null 2>&1 || D=0
git rev-parse --verify -q staging      >/dev/null 2>&1 || D=0
git rev-parse --verify -q refs/tags/v1.0 >/dev/null 2>&1 || D=0
git for-each-ref refs/heads | grep -q 'refs/heads/legacy' || D=0
cnt=$(git rev-list --all --count 2>/dev/null)
[ "$cnt" = "5" ] || D=0
if git fsck --full 2>&1 | grep -E '^missing|^broken' >/dev/null; then D=0; fi
if [ -f .git/ORIG_HEAD ] && [ -s .git/ORIG_HEAD ]; then
  oh=$(cat .git/ORIG_HEAD)
  hh=$(git rev-parse HEAD 2>/dev/null)
  if [ "$oh" != "$hh" ]; then
    if git cat-file -e "$oh" 2>/dev/null && git cat-file -p "$oh" 2>/dev/null | grep -aqE 'AKIA|ghp_|github_pat_'; then
      D=0
    fi
  fi
fi

# E: repository hygiene: clean status, and NO stray credential-bearing files
#    anywhere under /app except the designated recovery copy.
[ -z "$(git status --porcelain 2>/dev/null)" ] || E_bad=1
if grep -rqaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE" .git --include='*' 2>/dev/null | grep -av '/objects/' >/dev/null; then E_bad=1; fi
for f in README.md deploy.py inventory.html config.py legacy.txt; do
  if [ -f "$f" ] && ! grep -qaF '<REDACTED>' "$f" 2>/dev/null; then
    # missing placeholder is only ok if the file never had a credential
    if grep -qaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE" "$f" 2>/dev/null; then
      E_bad=1
    fi
  fi
done
# no stray credential-bearing files outside repo/recovery
if find /app -maxdepth 2 -type f ! -path '/app/repo/*' ! -path '/app/recovery/*' 2>/dev/null | while read -r f; do
    grep -qaF -e "$AWS_ID" -e "$AWS_SECRET" -e "$GH_PAT" -e "$GH_FINE" "$f" 2>/dev/null && echo HIT
  done | grep -q HIT; then
  E_bad=1
fi
[ -z "${E_bad:-}" ] && E=1

reward=$(awk "BEGIN{printf \"%.2f\", $A*0.2+$B*0.2+$C*0.2+$D*0.2+$E*0.2}")
echo "$reward" > /logs/verifier/reward.txt