#!/bin/bash
# Verifier for item-014-hard: multi-ref push + isolation + deletion + overwrite of stale content.
mkdir -p /logs/verifier

outm=""; outd=""; outmg=""
GIT_SSH_COMMAND='ssh -i /app/deploy/keys/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8'
export GIT_SSH_COMMAND

rm -rf /tmp/hclient && mkdir -p /tmp/hclient
A="HARDMAIN_$(date +%s)__K1"
B="HARDDEV_$(date +%s)__K2"

deploy_base=0
if git clone git@localhost:/srv/git/site.git /tmp/hclient/repo 2>/dev/null; then
  cd /tmp/hclient/repo
  git config user.name hclient
  git config user.email hclient@example.com

  # branch main -> A
  echo "<html><body><h1>$A</h1></body></html>" > index.html
  git add index.html
  git commit -qm 'main'
  git branch -M main

  # branch dev -> B
  git checkout -qb dev
  echo "<html><body><h1>$B</h1></body></html>" > index.html
  git add index.html
  git commit -qm 'dev'

  # push BOTH refs in one command
  git push origin main dev -q 2>/dev/null

  # temp branch then delete it
  git checkout -qb tempxyz main
  echo '<html>tmp</html>' > index.html
  git add index.html
  git commit -qm 'temp'
  git push origin tempxyz -q 2>/dev/null
  git push origin :tempxyz -q 2>/dev/null

  sleep 1
  body8443=$(curl -sk --connect-timeout 8 https://localhost:8443/ 2>/dev/null)
  body8445=$(curl -sk --connect-timeout 8 https://localhost:8445/ 2>/dev/null)
  cd /
  deploy_base=1
fi
tmpx_gone=$([ -d /srv/www/tempxyz ] && echo 0 || echo 1)

reward=$(python3 - "$body8443" "$body8445" "$A" "$B" "$tmpx_gone" "$deploy_base" <<'PY'
import sys, os
m84, d85, A, B, delete, base = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
points = 0
# multi-ref pushes reached the server at all
if base: points += 20
# main served on 8443, dev served on 8445, and they do not cross-contaminate
mmA = A in m84; mnB = B not in m84
ddB = B in d85; dnA = A not in d85
if mmA and mnB and ddB and dnA:
    points += 60
elif mmA or ddB:
    points += 30
# deletion removed the branch deploy dir
if delete == 1:
    points += 20
print(f"{points/100.0:.2f}")
PY
)
[ -z "$reward" ] && reward="0.00"
echo "$reward" > /logs/verifier/reward.txt