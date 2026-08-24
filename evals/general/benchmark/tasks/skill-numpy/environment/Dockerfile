FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy

RUN python3 - <<'PYEOF'
A = [[4, 1, -3],
     [2, 0, 7],
     [-1, 5, 3]]
B = [[2, 3, 1],
     [-2, 4, 0],
     [6, -1, 5]]
with open('/app/A.txt', 'w') as f:
    for row in A:
        f.write(' '.join(str(x) for x in row) + '\n')
with open('/app/B.txt', 'w') as f:
    for row in B:
        f.write(' '.join(str(x) for x in row) + '\n')
PYEOF