#!/bin/bash
set -euo pipefail

cat > /etc/nginx/nginx.conf <<'EOF'
worker_processes 1;
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;

    limit_req_zone $binary_remote_addr zone=api_limit:1m rate=1r/s;
    limit_req_status 429;

    log_format api_log '$remote_addr - [$time_local] "$request" $status';

    server {
        listen 8000;
        server_name localhost;

        location = /status {
            limit_req zone=api_limit burst=5 nodelay;
            access_log /var/log/nginx/api_access.log api_log;
            alias /app/ok.txt;
        }
    }
}
EOF

# validate before reload
nginx -t

# start if not running, then reload
if ! pgrep -x nginx >/dev/null 2>&1; then
  nginx
else
  nginx -s reload
fi
sleep 0.3

# smoke: one normal + one throttled burst
curl -s -o /dev/null -w "normal=%{http_code}\n" http://127.0.0.1:8000/status
burst=0
for i in $(seq 1 15); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/status)
  if [ "$code" = "429" ]; then burst=$((burst + 1)); fi
done
echo "throttled_429_count=$burst"