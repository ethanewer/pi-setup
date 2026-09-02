FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/items.json <<'EOF'
[
  {"name": "a", "weight": 2.5, "unit": "kg"},
  {"name": "b", "weight": 1000, "unit": "g"},
  {"name": "c", "weight": 50, "unit": "lb"},
  {"name": "d", "weight": 16, "unit": "oz"}
]
EOF