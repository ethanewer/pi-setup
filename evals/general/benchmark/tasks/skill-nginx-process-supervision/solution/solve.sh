#!/bin/bash
set -euo pipefail

cat > /app/nginx.conf <<'EOF'
worker_processes 4;
events { worker_connections 256; }
pid /tmp/nginx_super.pid;
error_log /tmp/nginx_super_error.log;
http {
    access_log /tmp/nginx_super_access.log;
    server {
        listen 8092;
        server_name localhost;
        root /app/www;
    }
}
EOF

# Clean restart so exactly the configured workers exist.
nginx -c /app/nginx.conf -s stop 2>/dev/null || true
sleep 0.2
nginx -c /app/nginx.conf
sleep 0.4

count=$(ps -axo args= | grep -E '^nginx: worker process$' | wc -l)
echo "running_workers=$count" > /app/supervision.txt