#!/bin/bash
set -euo pipefail

# The route handlers must be served by an actual content handler.  A `return`
# directive completes in the rewrite phase, BEFORE the pre-access limit_req
# phase, so it would bypass rate limiting.  We serve the two routes from small
# static files instead (status 200, body "ok").
mkdir -p /var/www/nginx
printf 'ok\n' > /var/www/nginx/api
printf 'ok\n' > /var/www/nginx/auth

cat > /etc/nginx/nginx.conf <<'EOF'
worker_processes 1;
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;

    limit_req_zone $binary_remote_addr zone=api_limit:1m rate=5r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:1m rate=1r/s;
    limit_req_status 429;

    log_format api_log '$remote_addr - [$time_local] "$request" $status';

    server {
        listen 8000;
        server_name localhost;

        location = /api {
            limit_req zone=api_limit burst=5 nodelay;
            access_log /var/log/nginx/api_access.log api_log;
            root /var/www/nginx;
            default_type text/plain;
        }
        location = /auth {
            limit_req zone=auth_limit burst=1 nodelay;
            access_log /var/log/nginx/api_access.log api_log;
            root /var/www/nginx;
            default_type text/plain;
        }
    }
}
EOF

nginx -t
if ! pgrep -x nginx >/dev/null 2>&1; then
  nginx
else
  nginx -s reload
fi
sleep 0.3

curl -s -o /dev/null -w "api_norm=%{http_code}\n" http://127.0.0.1:8000/api
curl -s -o /dev/null -w "auth_norm=%{http_code}\n" http://127.0.0.1:8000/auth

# Leave the service running for the verifier.
exit 0