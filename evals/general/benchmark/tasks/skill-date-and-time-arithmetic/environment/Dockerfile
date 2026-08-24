FROM bench-base:python-3.12

WORKDIR /app

# Each line: "<YYYY-MM-DD> <days-to-add>".
RUN cat > /app/dates.txt <<'EOF2'
2024-02-27 1
2024-02-28 1
2024-01-31 1
2023-12-30 5
2024-06-15 90
2023-03-01 -1
2024-12-31 1
EOF2
