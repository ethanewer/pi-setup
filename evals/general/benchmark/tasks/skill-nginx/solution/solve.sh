#!/bin/bash
set -euo pipefail

mkdir -p /app/www
printf 'Harbor nginx probe index\n' > /app/www/index.html

cat > /app/nginx.conf <<'EOF'
worker_processes 1;
events { worker_connections 256; }
pid /tmp/nginx_probe.pid;
error_log /tmp/nginx_probe_error.log;
http {
    access_log /tmp/nginx_probe_access.log;
    server {
        listen 8090;
        server_name localhost;
        root /app/www;
        add_header X-Harbor-Task nginx;
    }
}
EOF

# Make a clean start regardless of any previous run.
nginx -c /app/nginx.conf -s stop 2>/dev/null || true
sleep 0.2
nginx -c /app/nginx.conf
sleep 0.5

curl -s -i http://127.0.0.1:8090/ > /app/probe_result.txt