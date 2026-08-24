FROM bench-base:python-3.12

WORKDIR /app

# Records with dates to be validated against a date window.
RUN cat > /app/records.csv <<'EOF2'
id,entry_date
r1,2024-03-10
r2,2023-11-30
r3,2024-12-31
r4,2025-01-01
r5,2024-01-01
r6,2024-06-01
EOF2
