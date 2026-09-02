FROM bench-base:python-3.12

WORKDIR /app

# umber-larch: observational ATE estimation. numpy for the analysis.
RUN pip install --no-cache-dir numpy

# Visible observational study (deterministic; hidden studies are generated
# from the same DGP family with different seeds/params at authoring time).
RUN python3 - <<'PY'
import csv
import json
import numpy as np

rng = np.random.default_rng(4242)
N = 9000
a, b1, b2, sigma, m = 1.1, 0.55, 0.4, 1.0, 0.9
T, Y, C1, C2, I, P, M, K = ("treat", "outcome", "school_rating", "rural",
                            "slot_offer", "zip_noise", "attendance", "review_score")

def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))

c1 = rng.normal(0.0, 1.0, N)
c2 = (rng.random(N) < 0.4).astype(float)
i = (rng.random(N) < 0.5).astype(float)
t = (rng.random(N) < sigmoid(0.9 * i - 0.8 * c1 + 0.7 * c2 - 0.3)).astype(float)
med = 0.8 * t + 0.3 * c1 + rng.normal(0.0, 0.7, N)
y = (a * t + b1 * t * c1 + b2 * t * c2 + m * med
     + 0.9 * c1 + 0.7 * c2 + 0.5 * c1 ** 2 + rng.normal(0.0, sigma, N))
coll = 1.0 * t + 0.8 * y + rng.normal(0.0, 0.8, N)

cols = [C1, C2, I, P, T, M, K, Y]
data = {C1: c1, C2: c2, I: i, P: rng.normal(0, 1, N), T: t, M: med, K: coll, Y: y}
with open("/app/obs.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(cols)
    for r in range(N):
        w.writerow([data[c][r] for c in cols])
dag = {
    "nodes": [C1, C2, I, P, T, M, Y, K],
    "edges": [
        [I, T], [C1, T], [C2, T],
        [C1, Y], [C2, Y], [T, Y], [M, Y],
        [T, M], [C1, M],
        [T, K], [Y, K],
    ],
    "treatment_column": T,
    "outcome_column": Y,
}
with open("/app/dag.json", "w") as fh:
    json.dump(dag, fh, indent=2)
print("visible study written: %d rows" % N)
PY

ENV PYTHONUNBUFFERED=1
