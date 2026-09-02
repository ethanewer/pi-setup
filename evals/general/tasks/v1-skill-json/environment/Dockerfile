FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/config.json <<'EOF'
{"server": {"host": "db.internal", "port": 8087, "tls": true}, "name": "catalog", "debug": {"mode": "off", "cache_mb": 256}}
EOF