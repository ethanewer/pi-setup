FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy

RUN python3 - <<'PYEOF'
vals = [(i * 13 + 7) % 25 for i in range(50)]
with open('/app/scores.txt', 'w') as f:
    for v in vals:
        f.write(str(v) + '\n')
PYEOF