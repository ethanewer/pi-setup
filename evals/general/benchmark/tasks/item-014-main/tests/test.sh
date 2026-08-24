#!/bin/bash
# Verifier for item-014-main: pushes two branches over SSH and checks live HTTPS serving.
mkdir -p /logs/verifier

# ---- static shape checks ----
has_repo=0; has_cert=0
if [ -d /srv/git/site.git ] && [ -f /srv/git/site.git/hooks/post-receive ]; then has_repo=1; fi
if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ]; then has_cert=1; fi

# ---- live client-side test: push two branches, verify per-branch isolation ----
out8443=""; out8444=""
GIT_SSH_COMMAND='ssh -i /app/deploy/keys/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8'
export GIT_SSH_COMMAND

rm -rf /tmp/client && mkdir -p /tmp/client
A="MAIN_$(date +%s)__ALPHA"
B="STAG_$(date +%s)__BETA"

if git clone git@localhost:/srv/git/site.git /tmp/client/repo 2>/dev/null; then
  cd /tmp/client/repo
  git config user.name client
  git config user.email client@example.com

  echo "<html><body><h1>$A</h1></body></html>" > index.html
  git add index.html
  git commit -qm 'main push'
  git branch -M main
  git push -u origin main -q 2>/dev/null

  git checkout -qb staging
  echo "<html><body><h1>$B</h1></body></html>" > index.html
  git add index.html
  git commit -qm 'staging push'
  git push -u origin staging -q 2>/dev/null

  sleep 1
  out8443=$(curl -sk --connect-timeout 8 https://localhost:8443/ 2>/dev/null)
  out8444=$(curl -sk --connect-timeout 8 https://localhost:8444/ 2>/dev/null)
  cd /
else
  out8443=""; out8444=""
fi

# ---- award (python computes a 0..1 fraction) ----
reward=$(python3 - "$out8443" "$out8444" "$A" "$B" "$has_repo" "$has_cert" <<'PY'
import sys
m83, s, A, B, repo, cert = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
points = 0
if repo: points += 20
if cert: points += 10
mm = A in m83; mn = B not in m83
sh = B in s; sn = A not in s
if mm and mn and sh and sn:
    points += 70
elif mm or sh:
    points += 35
if not m83 and not s:
    points = min(points, 30)
print(f"{points/100.0:.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt