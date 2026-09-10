#!/usr/bin/env bash
# Yoke-inlet reference solver: writes the three deliverables exactly as a
# correct agent would, then proves the stack comes up.
set -euo pipefail

mkdir -p /app/tls /app/logs /app/run

# ---------------------------------------------------------------------------
# 1) TLS material: fresh self-signed CA + server certificate signed by it.
#    The server cert must verify (chain + hostname) for https://127.0.0.1.
# ---------------------------------------------------------------------------
CA_KEY=/app/tls/ca.key
CA_CRT=/app/tls/ca.crt
SVR_KEY=/app/tls/server.key
SVR_CRT=/app/tls/server.crt

rm -f "$CA_KEY" "$CA_CRT" "$SVR_KEY" "$SVR_CRT" /app/tls/ca.srl
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
    -keyout "$CA_KEY" -out "$CA_CRT" \
    -subj "/CN=Yoke Inlet Test CA" >/dev/null 2>&1

openssl req -newkey rsa:2048 -nodes -sha256 \
    -keyout "$SVR_KEY" -out /tmp/yoke-inlet.csr \
    -subj "/CN=localhost" >/dev/null 2>&1

cat > /app/run/san.ext <<'EXT'
subjectAltName=DNS:localhost,IP:127.0.0.1
EXT

openssl x509 -req -in /tmp/yoke-inlet.csr -sha256 -days 30 \
    -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -extfile /app/run/san.ext -out "$SVR_CRT" >/dev/null 2>&1
rm -f /tmp/yoke-inlet.csr

chmod 644 "$CA_CRT" "$SVR_CRT"
chmod 600 "$SVR_KEY"

# ---------------------------------------------------------------------------
# 2) nginx configuration
# ---------------------------------------------------------------------------
cat > /app/nginx.conf <<'NGINX'
worker_processes 1;
error_log /app/logs/error.log warn;
pid /app/run/nginx.pid;

events {
    worker_connections 256;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 10s;

    # Runtime temp dirs must live under /app so an unprivileged nginx can start.
    client_body_temp_path /app/run/tmp/client_body;
    proxy_temp_path /app/run/tmp/proxy;
    fastcgi_temp_path /app/run/tmp/fastcgi;
    uwsgi_temp_path /app/run/tmp/uwsgi;
    scgi_temp_path /app/run/tmp/scgi;

    access_log off;

    log_format yoke_inlet_format 'YOKE|$time_iso8601|$request|$status|$body_bytes_sent|$upstream_addr|$upstream_response_time|$request_time|$http_user_agent';

    # Weighted canary split: two requests to the canary for every one to stable.
    upstream yoke_pool {
        server 127.0.0.1:8123 weight=2 max_fails=2 fail_timeout=5s;  # canary
        server 127.0.0.1:8124 weight=1 max_fails=2 fail_timeout=5s;  # stable
    }

    server {
        listen 127.0.0.1:8443 ssl;
        server_name localhost;

        ssl_certificate     /app/tls/server.crt;
        ssl_certificate_key /app/tls/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        access_log /app/logs/access.log yoke_inlet_format;

        location / {
            proxy_pass http://yoke_pool;
            proxy_set_header Host $host;
            proxy_connect_timeout 2s;
            proxy_read_timeout 5s;
            # health-based failover: a request that lands on a dead peer is
            # retried on a live one instead of being answered with an error.
            proxy_next_upstream error timeout http_502 http_503 http_504;
        }
    }
}
NGINX

# ---------------------------------------------------------------------------
# 3) idempotent stack supervisor
# ---------------------------------------------------------------------------
cat > /app/start.sh <<'START'
#!/usr/bin/env bash
# Yoke-inlet stack supervisor.  Idempotent: safe to run repeatedly and from
# any prior state; never needs root.
set -u

CANARY_PORT=8123
STABLE_PORT=8124
FRONT_PORT=8443
HOST=127.0.0.1
CA=/app/tls/ca.crt
NGINX_CONF=/app/nginx.conf

mkdir -p /app/logs /app/run/tmp
chmod 1777 /app/logs /app/run /app/run/tmp 2>/dev/null || true

stop_one() { # $1 = tcp port
    fuser -k "$1/tcp" 2>/dev/null || true
}

stop_stack() {
    pkill -x nginx 2>/dev/null || true
    pkill -f '[u]pstreams/app_server.py' 2>/dev/null || true
    stop_one "$CANARY_PORT"; stop_one "$STABLE_PORT"; stop_one "$FRONT_PORT"
    sleep 0.3
}

# TLS material must exist before nginx can start.
if [ ! -f "$CA" ] || [ ! -f /app/tls/server.crt ]; then
    echo "yoke: missing TLS material under /app/tls - provision it first" >&2
    exit 1
fi

if curl -sS --cacert "$CA" -o /dev/null -w '%{http_code}' \
       "https://$HOST:$FRONT_PORT/healthz" 2>/dev/null | grep -q '^200$'; then
    echo "yoke: stack already serving; nothing to do"
    exit 0
fi

stop_stack

nohup python3 /app/upstreams/app_server.py --name canary --port "$CANARY_PORT" \
    > /app/logs/canary.log 2>&1 &
nohup python3 /app/upstreams/app_server.py --name stable --port "$STABLE_PORT" \
    > /app/logs/stable.log 2>&1 &

if ! nginx -t -c "$NGINX_CONF" >/dev/null 2>&1; then
    echo "yoke: nginx config invalid" >&2
    nginx -t -c "$NGINX_CONF" >&2
    exit 1
fi
nginx -c "$NGINX_CONF"

for _ in $(seq 1 40); do
    if curl -sS --cacert "$CA" -o /dev/null -w '%{http_code}' \
            "https://$HOST:$FRONT_PORT/healthz" 2>/dev/null | grep -q '^200$'; then
        echo "yoke: stack ready"
        exit 0
    fi
    sleep 0.5
done

echo "yoke: stack did not become ready" >&2
tail -5 /app/logs/error.log 2>/dev/null >&2 || true
exit 1
START

chmod +x /app/start.sh

# ---------------------------------------------------------------------------
# 4) prove the stack comes up and serves (same check the verifier makes)
# ---------------------------------------------------------------------------
bash /app/start.sh
curl -sS --cacert "$CA_CRT" -o /dev/null "https://127.0.0.1:8443/mortar"
echo "yoke-inlet reference stack is up"