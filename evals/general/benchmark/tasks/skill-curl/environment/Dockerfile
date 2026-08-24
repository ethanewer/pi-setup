FROM bench-base:ubuntu-24.04

WORKDIR /app

# Static content to be served over HTTP by a local server.
RUN mkdir -p /app/webroot/public && cat > /app/webroot/public/sample.json <<'EOF'
{"service":"demo","probe":42,"active":true}
EOF