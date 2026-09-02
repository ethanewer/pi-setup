#!/bin/bash
# mica-marsh oracle: author /app/probe_mlp.py, then run it against the visible
# fixture to produce /app/rows.json. Never reads /tests.
set -eu

cat > /app/probe_mlp.py <<'PY'
"""mica-marsh: recover v_i * w_i rows of a ReLU MLP from forward queries only.

Method: along each coordinate axis x = t * e_d the network is piecewise
linear in t with a kink at t = -b_i / w_i[d] for every unit with w_i[d] != 0.
The centered second difference of f over a grid cell is a signed triangular
spike at each kink whose centroid localizes t*. Crossing a kink changes the
full numerical gradient by exactly +- v_i * w_i, so sampling the gradient on
both sides of each kink (delta away from it) recovers a full row. Rows found
along several axes are deduplicated up to sign.
"""
import json


def extract_rows(query, in_dim):
    import numpy as np

    in_dim = int(in_dim)
    rows = []  # list of np.ndarray

    def same_row(a, b):
        na, nb = np.linalg.norm(a), np.linalg.norm(b)
        if na < 1e-12 or nb < 1e-12:
            return False
        return (np.linalg.norm(a - b) / nb < 1e-6 or
                np.linalg.norm(a + b) / nb < 1e-6)

    span = 9.0
    step = 0.01
    delta = 1e-3   # distance either side of a kink for gradient sampling
    gstep = 1e-5   # central-difference step
    thr = 1e-6     # spike threshold for the second difference

    for d in range(in_dim):
        e = np.zeros(in_dim)
        e[d] = 1.0
        ts = np.arange(-span, span + step, step)
        vals = np.array([query(t * e) for t in ts])
        s = vals[2:] - 2 * vals[1:-1] + vals[:-2]  # signed spikes, centers ts[1:-1]
        centers = ts[1:-1]
        idx = [i for i in range(len(s)) if abs(s[i]) > thr]
        # group consecutive indices (one spike may span 2-3 cells)
        groups = []
        for i in idx:
            if groups and i == groups[-1][-1] + 1:
                groups[-1].append(i)
            else:
                groups.append([i])
        for g in groups:
            wsum = sum(s[i] for i in g)
            if abs(wsum) < 1e-12:
                continue
            t_star = float(sum(centers[i] * s[i] for i in g) / wsum)
            x1 = (t_star - delta) * e
            x2 = (t_star + delta) * e

            def grad(x):
                gv = np.zeros(in_dim)
                for k in range(in_dim):
                    xp = np.array(x, dtype=float)
                    xm = np.array(x, dtype=float)
                    xp[k] += gstep
                    xm[k] -= gstep
                    gv[k] = (query(xp) - query(xm)) / (2 * gstep)
                return gv

            row = grad(x2) - grad(x1)
            if np.linalg.norm(row) < 1e-9:
                continue
            if not any(same_row(row, prev) for prev in rows):
                rows.append(row)

    return [list(map(float, r)) for r in rows]


def _load_blackbox(path):
    import importlib.util
    import numpy as np  # noqa: F401  (fixture module needs it importable)
    spec = importlib.util.spec_from_file_location("blackbox_fixture", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.BlackBox()


def main():
    model = _load_blackbox("/app/blackbox.py")
    rows = extract_rows(model.query, model.in_dim)
    with open("/app/rows.json", "w") as fh:
        json.dump({"rows": rows, "n_rows": len(rows)}, fh, indent=2)
    print("wrote /app/rows.json with %d rows" % len(rows))


if __name__ == "__main__":
    main()
PY

python3 /app/probe_mlp.py

echo "solve.sh done -> /app/probe_mlp.py and /app/rows.json"
ls -l /app/probe_mlp.py /app/rows.json
