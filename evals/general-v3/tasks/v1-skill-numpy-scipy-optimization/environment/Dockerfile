FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy scipy

RUN python3 - <<'PYEOF'
import csv, math, random
random.seed(7)          # deterministic noise
rows = []
for i in range(20):
    t = float(i)
    noise = random.gauss(0.0, 0.05)
    y = 3.0 * math.exp(-0.8 * t) + noise
    rows.append((t, y))
with open('/app/decay.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['t', 'y'])
    w.writerows(rows)
PYEOF