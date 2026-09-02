FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
rows = []
for i in range(60):
    A = i % 2
    B = (A + ((i // 4) % 2)) % 2
    C = (i * 5) % 2
    D = (i * 7) % 3
    rows.append([A, B, C, D])
with open('/app/data.csv', 'w') as f:
    f.write('A,B,C,D\n')
    for r in rows:
        f.write(','.join(str(x) for x in r) + chr(10))
PYEOF
