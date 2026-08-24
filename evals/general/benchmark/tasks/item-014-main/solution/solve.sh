#!/bin/bash
# Oracle solution: builds the deployment pipeline and leaves it running.
set -uo pipefail

# 1. Ensure host keys + sshd running
mkdir -p /run/sshd
ssh-keygen -A 2>/dev/null
if ! pidof sshd >/dev/null 2>&1; then
  sshd
  sleep 1
fi

# 2. Create the bare repository + post-receive hook
mkdir -p /srv/git
if [ ! -d /srv/git/site.git ]; then
  git init --bare /srv/git/site.git
fi
chown -R git:git /srv/git/site.git

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

# ensure www dirs world-usable by the git account
chown -R git:git /srv/www 2>/dev/null || true

# 3. Self-signed TLS cert
mkdir -p /etc/nginx/ssl
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/nginx/ssl/privkey.pem \
  -out /etc/nginx/ssl/fullchain.pem \
  -days 3650 -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost" 2>/dev/null

# 4. Nginx config (minimal but valid)
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
VHOST

# initial deploy dirs (so nginx can start even before first push)
mkdir -p /srv/www/main /srv/www/staging
if [ ! -f /srv/www/main/index.html ]; then
  echo "<h1>main initial</h1>" > /srv/www/main/index.html
  echo "<h1>staging initial</h1>" > /srv/www/staging/index.html
fi
chmod 777 /srv/www/main /srv/www/staging 2>/dev/null || chown -R git:git /srv/www

# 5. Start nginx
nginx -t >/dev/null 2>&1 || true
nginx 2>/dev/null || true
sleep 1

# 6. Client-side smoke test (exercises the pipeline end to end)
GIT_SSH_COMMAND='ssh -i /app/deploy/keys/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
export GIT_SSH_COMMAND
rm -rf /tmp/smoke && mkdir -p /tmp/smoke
cd /tmp/smoke
git init -q
git config user.name smoke; git config user.email smoke@example.com
echo '<h1>CLIENTSOME_X</h1>' > index.html
git add index.html
git commit -qm 'deploy main'
git branch -M main
git -c remote.origin.url="git@localhost:/srv/git/site.git" push origin main -q
cd /
rm -rf /tmp/smoke

exit 0