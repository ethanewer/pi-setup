#!/bin/bash
# Verifier for zephyr-helix.
# Executes /app/integrate.py and /app/eig.py on the hidden cases under
# /tests/hidden, recomputes references independently (scipy expm for the linear
# ODE, numpy.linalg.eig for the spectra), and confirms malformed cases yield a
# clean ERR/non-zero exit with no valid output file.
# Always ends by writing /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

H=/tests/hidden
TMP=/tmp/v2t
rm -rf "$TMP"; mkdir -p "$TMP"

[ -f /app/integrate.py ] || fail "integrate.py missing"
[ -f /app/eig.py ]       || fail "eig.py missing"

# ----------------------------------------------------------------------
# Integrator: one good hidden case
# ----------------------------------------------------------------------
check_integ() {
  local c="$1"
  python3 "/app/integrate.py" "$H/$c.json" "$TMP/$c.out" >"$TMP/$c.log" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then fail "integrate $c (exit $rc)"; return; fi
  python3 - "$H" "$c" "$TMP" <<'PY'
import json, sys
import numpy as np
from scipy.linalg import expm
H, c, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
case = json.load(open("%s/%s.json" % (H, c)))
od   = json.load(open("%s/%s.out" % (TMP, c)))
M  = np.asarray(case["M"], dtype=float)
t0,t1 = float(case["t0"]), float(case["t1"])
y0 = np.asarray(case["y0"], dtype=float)
atol, rtol = float(case["atol"]), float(case["rtol"])
npts, budget = int(case["n_points"]), int(case["budget"])
T = np.linspace(t0, t1, npts)
Y = np.asarray(od.get("y"), dtype=float)
if od.get("status") != "ok":
    print("ERR status"); sys.exit(1)
if Y.shape != (npts, y0.shape[0]):
    print("ERR shape", Y.shape); sys.exit(1)
if np.any(~np.isfinite(Y)):
    print("ERR nan/inf"); sys.exit(1)
nfev = od.get("nfev")
if not (isinstance(nfev, int) and 1 <= nfev <= budget):
    print("ERR nfev", nfev); sys.exit(1)
for k in range(npts):
    ref = expm(M * (T[k] - t0)).dot(y0)
    tol = 10.0*atol + 20.0*rtol*np.max(np.abs(ref))
    if np.max(np.abs(Y[k] - ref)) > tol:
        print("ERR accuracy at %.4f" % T[k]); sys.exit(1)
sys.exit(0)
PY
  if [ "$?" -ne 0 ]; then fail "integrate $c (numeric)"; fi
}

# bad integrator case must exit non-zero, print ERR, and leave no out file
python3 /app/integrate.py "$H/integ_bad.json" "$TMP/bad.out" >"$TMP/bad.log" 2>&1
if [ "$?" -eq 0 ] || ! grep -q "^ERR:" "$TMP/bad.log" || [ -f "$TMP/bad.out" ]; then
  fail "integrate bad-case not rejected"
fi

check_integ integ_steady
check_integ integ_stark

# ----------------------------------------------------------------------
# eig.py: largest-magnitude (complex + negative-real traps) and principal
# ----------------------------------------------------------------------
run_eig() { python3 /app/eig.py "$@"; }

# largest on complex pair
python3 /app/eig.py largest "$H/eig_complex.json" "$TMP/eig_c.out" >"$TMP/eig_c.log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then fail "eig largest complex exit $rc"; else
python3 - "$H/eig_complex.json" "$TMP/eig_c.out" <<'PY'
import json, sys
import numpy as np
A = np.asarray(json.load(open(sys.argv[1]))["M"], dtype=complex)
o = json.load(open(sys.argv[2]))
z = complex(o["re"], o["im"])
w = np.linalg.eigvals(A); w = w[np.isfinite(w)]
m = np.max(np.abs(w))
if not np.isfinite(abs(z)) or abs(abs(z) - m) > 1e-8: sys.exit(1)
if not any(abs(z - x) <= 1e-7 for x in w): sys.exit(1)
sys.exit(0)
PY
[ "$?" -ne 0 ] && fail "eig largest complex"
fi

# largest magnitude on a real matrix -> must choose magnitude, not real part
python3 /app/eig.py largest "$H/eig_sign.json" "$TMP/eig_s.out" >"$TMP/eig_s.log" 2>&1 && {
python3 - "$H/eig_sign.json" "$TMP/eig_s.out" <<'PY'
import json, sys
import numpy as np
A = np.asarray(json.load(open(sys.argv[1]))["M"], dtype=complex)
o = json.load(open(sys.argv[2]))
z = complex(o["re"], o["im"])
w = np.linalg.eigvals(A); w = w[np.isfinite(w)]
m = np.max(np.abs(w))
if abs(abs(z) - m) > 1e-8 or not any(abs(z - x) <= 1e-7 for x in w):
    sys.exit(1)
sys.exit(0)
PY
[ "$?" -ne 0 ] && fail "eig largest sign"
}

# principal-minor spectra
python3 /app/eig.py principal "$H/eig_principal.json" "$TMP/eig_p.out" >"$TMP/eig_p.log" 2>&1
if [ "$?" -ne 0 ]; then fail "eig principal exit"; else
python3 - "$H/eig_principal.json" "$TMP/eig_p.out" <<'PY'
import json, sys
import numpy as np
A = np.asarray(json.load(open(sys.argv[1]))["M"], dtype=complex)
o = json.load(open(sys.argv[2]))
sp = o["spectra"]
n = A.shape[0]
if len(sp) != n: print("len"); sys.exit(1)
for k in range(1, n+1):
    got = [complex(a,b) for a,b in sp[k-1]]
    ref = np.linalg.eigvals(A[:k,:k])
    ref = ref[np.isfinite(ref)]
    if len(got) != k: sys.exit(1)
    # one-to-one magnitude-preserving match
    used = [False]*k
    for g in got:
        best = min(range(k), key=lambda j: abs(g - ref[j]) if not used[j] else 1e9)
        if abs(g - ref[best]) > 1e-7: sys.exit(1)
        used[best] = True
     # magnitude ordering check
    mags = [abs(g) for g in got]
    if any(mags[i] < mags[i+1] - 1e-9 for i in range(k-1)): sys.exit(1)
sys.exit(0)
PY
[ "$?" -ne 0 ] && fail "eig principal"
fi

# bad matrix must be ERR and no out file
rm -f "$TMP/eig_b.out"
python3 /app/eig.py largest "$H/eig_bad.json" "$TMP/eig_b.out" >"$TMP/eig_b.log" 2>&1
if [ "$?" -eq 0 ] || ! grep -q "^ERR:" "$TMP/eig_b.log" || [ -f "$TMP/eig_b.out" ]; then
  fail "eig bad-case not receiving ERR"
fi

# ----------------------------------------------------------------------
if [ "$PASS" = "1" ]; then reward=1; fi
echo "zephyr-helix reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0