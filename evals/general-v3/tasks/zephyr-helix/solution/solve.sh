#!/bin/bash
# Oracle for zephyr-helix. Writes the two deliverable programs into /app and
# marks them executable. Reads nothing from /tests.
set -euo pipefail

cat > /app/integrate.py <<'PYEOF'
#!/usr/bin/env python3
"""Helix Dynamics linear ODE/IVP integrator with a hard RHS-evaluation ceiling.

Usage: python3 integrate.py <case.json> <out.json>

Solves dy/dt = M.y on [t0, t1] and writes a trajectory sampled on a uniform
grid, honouring a hard ceiling on the number of RHS evaluations and staying
within an error tolerance of the exact exp(M t) solution.
"""
import json
import sys

import numpy as np
from scipy.integrate import solve_ivp


def _finite(x):
    try:
        return np.all(np.isfinite(np.asarray(x, dtype=float)))
    except (TypeError, ValueError):
        return False


def validate(case):
    """Return an error message string, or None when the case is sound."""
    if not isinstance(case, dict):
        return "case is not a JSON object"
    if case.get("system") != "linear":
        return "unsupported system (only 'linear')"
    for key in ("M", "t0", "t1", "y0", "budget", "atol", "rtol", "n_points"):
        if key not in case:
            return "missing required field '%s'" % key
    try:
        M = np.asarray(case["M"], dtype=float)
    except (TypeError, ValueError):
        return "M is not numeric"
    if M.ndim != 2 or M.shape[0] != M.shape[1]:
        return "M is not a square 2-D matrix"
    n = M.shape[0]
    if not (2 <= n <= 6):
        return "dimension outside range 2..6"
    if not _finite(M):
        return "M contains non-finite entries"
    try:
        t0 = float(case["t0"])
        t1 = float(case["t1"])
        y0 = np.asarray(case["y0"], dtype=float)
        budget = case["budget"]
        atol = float(case["atol"])
        rtol = float(case["rtol"])
        npts = case["n_points"]
    except (TypeError, ValueError):
        return "non-numeric field value"
    if not (np.isfinite(t0) and np.isfinite(t1)):
        return "t0/t1 must be finite"
    if not t1 > t0:
        return "t1 must be strictly greater than t0"
    if y0.ndim != 1 or y0.shape[0] != n:
        return "y0 length must match M dimension"
    if not _finite(y0):
        return "y0 contains non-finite entries"
    if isinstance(budget, bool) or not isinstance(budget, (int, float)) \
            or float(budget) != int(budget) or int(budget) <= 0:
        return "budget must be a positive integer"
    if not (atol > 0 and rtol > 0):
        return "atol/rtol must be strictly positive"
    if isinstance(npts, bool) or not isinstance(npts, (int, float)) \
            or float(npts) != int(npts) or int(npts) < 2:
        return "n_points must be an integer >= 2"
    return None


def main(argv):
    if len(argv) != 3:
        print("ERR: expected usage: python3 integrate.py <case.json> <out.json>",
              file=sys.stderr)
        return 2
    case_path, out_path = argv[1], argv[2]
    try:
        with open(case_path) as fh:
            case = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print("ERR: cannot read case JSON: %s" % exc, file=sys.stderr)
        return 1

    err = validate(case)
    if err is not None:
        print("ERR: %s" % err, file=sys.stderr)
        return 1

    M = np.asarray(case["M"], dtype=float)
    t0, t1 = float(case["t0"]), float(case["t1"])
    y0 = np.asarray(case["y0"], dtype=float)
    budget = int(case["budget"])
    atol, rtol = float(case["atol"]), float(case["rtol"])
    npts = int(case["n_points"])

    teval = np.linspace(t0, t1, npts)
    rhs_calls = {"n": 0}

    def rhs(_t, y):
        rhs_calls["n"] += 1
        return M.dot(y)

    # Scale-dependent max step keeps the count naturally bounded and the
    # trajectory accurate; the outer budget ceiling is still enforced below.
    span = t1 - t0
    max_step = span / max(1.0, 8.0 * (npts - 1))
    sol = solve_ivp(rhs, (t0, t1), y0, method="RK45", t_eval=teval,
                    atol=atol, rtol=rtol, max_step=max_step)
    y = np.asarray(sol.y).T  # shape (npts, n)

    if rhs_calls["n"] > budget:
        print("ERR: RHS budget exceeded (%d > %d)"
              % (rhs_calls["n"], budget), file=sys.stderr)
        return 1

    out = {"status": "ok", "nfev": rhs_calls["n"], "y": y.tolist()}
    with open(out_path, "w") as fh:
        json.dump(out, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF

cat > /app/eig.py <<'PYEOF'
#!/usr/bin/env python3
"""Helix Dynamics spectral toolkit: largest-magnitude eigenvalue and
principal-minor spectra."""
import itertools
import json
import sys

import numpy as np


def load_matrix(case):
    """Return (A, err). A is a valid square float/complex array or None."""
    if not isinstance(case, dict):
        return None, "case is not a JSON object"
    if "M" not in case:
        return None, "missing required field 'M'"
    raw = case["M"]
    try:
        A = np.asarray(raw, dtype=complex)
    except (TypeError, ValueError):
        return None, "M is not numeric"
    if A.ndim != 2 or A.shape[0] != A.shape[1]:
        return None, "M is not a square 2-D matrix"
    n = A.shape[0]
    if not (2 <= n <= 8):
        return None, "dimension outside range 2..8"
    if not np.all(np.isfinite(A)):
        return None, "M contains non-finite entries"
    return A, None


def largest(A):
    w = np.linalg.eigvals(A)
    w = w[np.isfinite(w)]
    idx = int(np.argmax(np.abs(w)))
    z = complex(w[idx])
    return {"re": float(z.real), "im": float(z.imag),
            "mag": float(abs(z))}


def principal(A):
    n = A.shape[0]
    spectra = []
    for k in range(1, n + 1):
        sub = A[:k, :k]
        ev = np.linalg.eigvals(sub)
        ev = ev[np.isfinite(ev)]
        ordered = sorted(ev, key=lambda c: (-abs(c), -c.real, -c.imag))
        spectra.append([[float(c.real), float(c.imag)] for c in ordered])
    return {"spectra": spectra}


def _cmd(argv):
    if len(argv) != 4:
        print("ERR: expected usage: python3 eig.py <largest|principal> <in.json> <out.json>",
              file=sys.stderr)
        return 2
    sub, case_path, out_path = argv[1], argv[2], argv[3]
    if sub not in ("largest", "principal"):
        print("ERR: unknown subcommand '%s' (expected largest|principal)" % sub,
              file=sys.stderr)
        return 2
    try:
        with open(case_path) as fh:
            case = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print("ERR: could not read case JSON: %s" % exc, file=sys.stderr)
        return 1
    A, err = load_matrix(case)
    if err is not None:
        print("ERR: %s" % err, file=sys.stderr)
        return 1
    if sub == "largest":
        data = largest(A)
    else:
        data = principal(A)
    with open(out_path, "w") as fh:
        json.dump(data, fh)
    return 0


if __name__ == "__main__":
    sys.exit(_cmd(sys.argv))
PYEOF

chmod 755 /app/integrate.py /app/eig.py
echo "deliverables written"