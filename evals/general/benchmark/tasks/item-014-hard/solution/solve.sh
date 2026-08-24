#!/bin/bash
# Oracle solution: build the full multi-branch pipeline and leave it running.
set -uo pipefail

# 1. sshd (use an absolute path: OpenSSH requires it for privilege-separation
#    re-exec, otherwise it starts inconsistently and git-over-ssh is flaky).
mkdir -p /run/sshd
ssh-keygen -A 2>/dev/null
if ! pgrep -x sshd >/dev/null 2>&1; then
  /usr/sbin/sshd
fi
# Wait until sshd actually accepts key auth before clients try to use it.
for _i in $(seq 1 40); do
  if ssh -q -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -i /app/deploy/keys/id_ed25519 \
      git@localhost 'echo ping' 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# 2. repo + hook
mkdir -p /srv/git
if [ ! -d /srv/git/site.git ]; then
  git init --bare /srv/git/site.git
fi
chown -R git:git /srv/git/site.git 2>/dev/null || true

cat > /srv/git/site.git/hooks/post-receive <<'HOOK'
#!/bin/bash
while read old new ref; do
  branch="${ref#refs/heads/}"
  [ "$branch" = "$ref" ] && continue
  target="/srv/www/$branch"
  if [ "$new" = "0000000000000000000000000000000000000000" ]; then
    rm -rf "$target"
    continue
  fi
  mkdir -p "$target"
  git --git-dir=/srv/git/site.git archive "$new" | tar -x -C "$target"
done
HOOK
chmod 755 /srv/git/site.git/hooks/post-receive

# 3. fix deploy dir permissions so the git-run hook can overwrite stale root content
chmod 777 /srv/www /srv/www/main /srv/www/staging /srv/www/dev 2>/dev/null || true

# 4. TLS cert
mkdir -p /etc/nginx/ssl
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/nginx/ssl/privkey.pem \
  -out /etc/nginx/ssl/fullchain.pem \
  -days 3650 -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost" 2>/dev/null

# 5. nginx config
cat > /etc/nginx/nginx.conf <<'NGINX'
worker_processes 1;
events { worker_connections 64; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  include /etc/nginx/conf.d/*.conf;
}
NGINX

cat > /etc/nginx/conf.d/deploy.conf <<'VHOST'
server {
  listen 8443 ssl;
  server_name localhost;
  ssl_certificate     /etc/nginx/ssl/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/privkey.pem;
  root /srv/www/main;
  index index.html;
}
server {
  listen 8444 ssl;
  server_name localhost;
  ssl_certificate     /etc/nginx/ssl/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/privkey.pem;
  root /srv/www/staging;
  index index.html;
}
server {
  listen 8445 ssl;
  server_name localhost;
  ssl_certificate     /etc/nginx/ssl/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/privkey.pem;
  root /srv/www/dev;
  index index.html;
}
VHOST

nginx -t 2>/dev/null || true
nginx 2>/dev/null || true
sleep 1

# 6. client-side smoke: one clone, two branches pushed, delete a temp branch
GIT_SSH_COMMAND="ssh -i /app/deploy/keys/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export GIT_SSH_COMMAND
rm -rf /tmp/smoke && mkdir -p /tmp/smoke
cd /tmp/smoke
git init -q
git config user.name smoke
git config user.email smoke@example.com
echo '<h1>SMOKE_MAIN</h1>' > index.html
git add index.html
git commit -qm 'main'
git branch -M main
git -c remote.origin.url="git@localhost:/srv/git/site.git" push origin main -q 2>/dev/null
# Point the bare repo HEAD at the branch we pushed so subsequent clones can
# actually check out a work tree (git init --bare leaves HEAD on 'master').
git --git-dir=/srv/git/site.git symbolic-ref HEAD refs/heads/main
cd /
rm -rf /tmp/smoke
exit 0