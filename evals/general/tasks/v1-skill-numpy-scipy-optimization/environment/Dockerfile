FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

RUN pip install --disable-pip-version-check numpy==2.5.3 scipy==1.18.1

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