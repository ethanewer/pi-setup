FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/layers.json <<'EOF'
{"layers": [
  {"name": "light", "min": 0, "max": 10},
  {"name": "mid",   "min": 10, "max": 25},
  {"name": "deep",  "min": 25, "max": 40}
]}
EOF
RUN printf '0,5,10,12,24,25,30\n' > /app/depths.csv