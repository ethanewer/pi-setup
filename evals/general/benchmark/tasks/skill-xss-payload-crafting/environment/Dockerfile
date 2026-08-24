FROM bench-base:python-3.12

WORKDIR /app

# The server-side filter is intentionally NOT shipped in the image; only the
# verifier defines it. This empty marker keeps the environment self-contained.
RUN cat > /app/readme.txt <<'EOF'
Write your crafted XSS payload to /app/payload.txt
EOF