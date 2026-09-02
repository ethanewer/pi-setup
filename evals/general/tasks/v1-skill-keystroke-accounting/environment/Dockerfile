FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/keylog.json <<'EOF'
{"events": [
  {"key": "a", "press": 3},
  {"key": "b", "press": 1},
  {"key": "backspace", "press": 2},
  {"key": "a", "press": 4},
  {"key": "shift", "press": 6},
  {"key": "b", "press": 2}
]}
EOF