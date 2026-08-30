#!/bin/bash
# iron-lattice verifier: executes /app/power.py on the visible matrix and on
# hidden matrices, comparing eigenvalue (abs tol) and eigenvector (dot product).
set -u
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/power.py ]; then
  echo "missing /app/power.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

TMP=/tmp/iron_out.json
: > "$TMP"

check_case() {
  local input="$1" expected="$2"
  if ! python3 /app/power.py "$input" "$TMP"; then
    echo "power.py failed on $input" >&2
    return 1
  fi
  python3 - "$TMP" "$expected" <<'PY'
import json, sys, math
try:
    g = json.load(open(sys.argv[1]))
    e = json.load(open(sys.argv[2]))
except Exception as ex:
    print("bad json:", ex); raise SystemExit(1)
gv = [float(x) for x in g.get("vector", [])]
ev = [float(x) for x in e["vector"]]
ok = True
if abs(g.get("eigenvalue", 1e18) - e["eigenvalue"]) > 1e-6:
    print("eigenvalue out of tol:", g.get("eigenvalue"), e["eigenvalue"]); ok = False
if len(gv) != len(ev):
    print("vector length mismatch:", len(gv), len(ev)); ok = False
else:
    dot = abs(sum(gv[i]*ev[i] for i in range(len(ev))))
    nrm = math.sqrt(sum(x*x for x in gv))
    if (1.0 - dot) > 1e-6:
        print("vector dot out of tol:", dot); ok = False
    if abs(nrm - 1.0) > 1e-6:
        print("vector not unit:", nrm); ok = False
sys.exit(0 if ok else 1)
PY
}

allok=1
check_case /app/matrix.txt /tests/expected.json || allok=0

for d in /tests/hidden/*; do
  [ -d "$d" ] || continue
  check_case "$d/matrix.txt" "$d/expected.json" || allok=0
done

echo "$allok" > /logs/verifier/reward.txt