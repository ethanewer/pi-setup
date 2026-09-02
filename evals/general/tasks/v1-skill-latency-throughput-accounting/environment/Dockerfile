FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/transfers.json <<'EOF'
[
  {"name": "r1", "bytes": 10485760, "duration_sec": 2.0},
  {"name": "r2", "bytes": 1048576, "duration_sec": 0.5},
  {"name": "r3", "bytes": 2097152, "duration_sec": 1.0}
]
EOF