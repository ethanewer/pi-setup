#!/usr/bin/env python3
"""Generate mica-marsh fixtures: visible + hidden BlackBox modules and the
expected rows (v_i * w_i) with constraints that make probe-based extraction
clean (kink separation, hyperplane clearance, non-collinear rows)."""
import json
import os
import numpy as np

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEMPLATE = '''"""BlackBox fixture for mica-marsh (generated; deterministic).

The ONLY permitted channel is `query`; do not inspect private attributes
(they are not part of the contract).
"""
import numpy as np

_W = np.array({w!r}, dtype=float)   # (n_units, in_dim)
_V = np.array({v!r}, dtype=float)
_B = np.array({b!r}, dtype=float)


class BlackBox:
    in_dim = {in_dim}
    n_units = {n_units}

    def query(self, x):
        """f(x) = sum_i v_i * relu(w_i . x + b_i); x is array-like of length in_dim."""
        x = np.asarray(x, dtype=float).reshape(-1)
        if x.shape[0] != self.in_dim:
            raise ValueError("input length %d != in_dim %d" % (x.shape[0], self.in_dim))
        return float(np.sum(_V * np.maximum(_W @ x + _B, 0.0)))
'''


def gen_case(rng, in_dim, n_units, min_zero_frac=0.15):
    for _attempt in range(20000):
        W = np.zeros((n_units, in_dim))
        for i in range(n_units):
            pattern = rng.random(in_dim) > min_zero_frac
            if not pattern.any():
                pattern[rng.randrange(in_dim)] = True
            W[i][pattern] = rng.uniform(0.4, 1.5, size=pattern.sum()) * rng.choice([-1, 1], size=pattern.sum())
        V = rng.uniform(0.5, 1.8, size=n_units) * rng.choice([-1, 1], size=n_units)
        B = rng.uniform(-3.0, 3.0, size=n_units)

        # kink separation along shared directions
        ok = True
        tstar = {}
        for i in range(n_units):
            for d in range(in_dim):
                if W[i][d] != 0:
                    tstar[(i, d)] = -B[i] / W[i][d]
                    if abs(tstar[(i, d)]) > 8.0:
                        ok = False
        if not ok:
            continue
        sep_ok = True
        for i in range(n_units):
            for j in range(i + 1, n_units):
                for d in range(in_dim):
                    if (i, d) in tstar and (j, d) in tstar:
                        if abs(tstar[(i, d)] - tstar[(j, d)]) < 0.05:
                            sep_ok = False
        if not sep_ok:
            continue
        # hyperplane clearance at the +-1e-3 gradient sample points
        clear_ok = True
        for i in range(n_units):
            for d in range(in_dim):
                if (i, d) not in tstar:
                    continue
                delta = 1e-3
                for side in (-delta, delta):
                    x = np.zeros(in_dim)
                    x[d] = tstar[(i, d)] + side
                    for j in range(n_units):
                        if j == i:
                            continue
                        if abs(W[j] @ x + B[j]) < 1e-3:
                            clear_ok = False
        if not clear_ok:
            continue
        # rows A_i = v_i * w_i pairwise non-collinear and nonzero
        A = V[:, None] * W
        norms = np.linalg.norm(A, axis=1)
        if (norms < 1e-9).any():
            continue
        coll = False
        for i in range(n_units):
            for j in range(i + 1, n_units):
                c = abs(A[i] @ A[j] / (norms[i] * norms[j]))
                if c > 0.95:
                    coll = True
        if coll:
            continue
        return W, V, B
    raise RuntimeError("could not generate a clean case")


def write_case(dirname, in_dim, n_units, seed):
    rng = np.random.default_rng(seed)
    W, V, B = gen_case(rng, in_dim, n_units)
    os.makedirs(dirname, exist_ok=True)
    with open(os.path.join(dirname, "blackbox.py"), "w") as fh:
        fh.write(TEMPLATE.format(w=W.round(6).tolist(), v=V.round(6).tolist(),
                                 b=B.round(6).tolist(), in_dim=in_dim,
                                 n_units=n_units))
    rows = (V[:, None] * W).round(9).tolist()
    with open(os.path.join(dirname, "expected.json"), "w") as fh:
        json.dump({"in_dim": in_dim, "n_units": n_units, "rows": rows}, fh, indent=2)
    print(dirname, "in_dim=%d n_units=%d" % (in_dim, n_units))


def main():
    write_case(os.path.join(OUT, "tests", "hidden", "case-1"), 3, 5, 0xA1101)
    write_case(os.path.join(OUT, "tests", "hidden", "case-2"), 6, 8, 0xA1102)


if __name__ == "__main__":
    main()
