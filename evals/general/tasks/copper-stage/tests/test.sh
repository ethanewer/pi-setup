#!/bin/bash
# Verifier for copper-stage (executes-deliverable).
# Requires /app/solve.py, runs it on hidden boxes, and independently validates
# the results against a gold exhaustive scan. Deterministic, no network.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

reward=0

gold_scan() {
  # $1 = bounds file; prints JSON {"a","b","evaluations","score"} of gold optimum.
  python3 - "$1" <<'PY'
import json, sys
from sim import score
path = sys.argv[1]
raw = json.load(open(path))
if not isinstance(raw, dict) or set(raw) != {"a", "b"}:
    raise SystemExit("bad bounds")
box = {}
for k in ("a", "b"):
    lo, hi = raw[k]
    if not isinstance(lo, int) or not isinstance(hi, int) or lo > hi:
        raise SystemExit(f"bad {k} bounds")
    box[k] = (lo, hi)
(la, ha), (lb, hb) = box["a"], box["b"]
best = None
for a in range(la, ha + 1):
    for b in range(lb, hb + 1):
        s = score(a, b)
        if best is None or s > best[0] + 1e-12 or \
           (abs(s - best[0]) <= 1e-12 and (a < best[1] or (a == best[1] and b < best[2]))):
            best = (s, a, b)
s, a, b = best
evals = (ha - la + 1) * (hb - lb + 1)
print(json.dumps({"a": a, "b": b, "evaluations": evals, "score": s}))
PY
}

validate() {
  # $1 = actual tuning JSON path
  # $2 = gold JSON string
  python3 - "$1" "$2" <<'PY'
import json, sys
p, gs = sys.argv[1], sys.argv[2]
g = json.loads(gs)
try:
    a = json.load(open(p))
except Exception:
    print("NO-OUTPUT")
    raise SystemExit(1)
ok = (a.get("a") == g["a"] and a.get("b") == g["b"]
      and a.get("evaluations") == g["evaluations"])
if not ok:
    print(f"MISMATCH got={a} gold={g}")
    raise SystemExit(1)
if "score" not in a or not isinstance(a["score"], (int, float)):
    print("MISSING-SCORE")
    raise SystemExit(1)
if g["score"] == 0:
    ok_sc = abs(a["score"]) <= 1e-6
else:
    ok_sc = abs(a["score"] - g["score"]) <= 1e-6 * abs(g["score"])
if not ok_sc:
    print(f"SCORE got={a['score']} want≈{g['score']}")
    raise SystemExit(1)
print("OK")
PY
}

all_ok=1

# 1) Deliverable must exist and be a program.
if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py"
  all_ok=0
fi

# 2) Visible case: deliverable tuning.json must match gold on /app/bounds.json.
if [ "$all_ok" -eq 1 ] && [ ! -f /app/tuning.json ]; then
  echo "missing /app/tuning.json (visible output)"
  all_ok=0
fi
if [ "$all_ok" -eq 1 ]; then
  g=$(gold_scan /app/bounds.json) || { all_ok=0; }
  if ! validate /app/tuning.json "$g" >/dev/null; then
    echo "visible tuning.json failed"
    all_ok=0
  fi
fi

# 3) Hidden cases: run the produced program and validate each.
for dir in /tests/hidden/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  bfile="$dir/bounds.json"
  out="/tmp/out_${name}.json"
  rm -f "$out"
  if [ "$name" = "case_bad" ]; then
    # malformed input: program must fail cleanly (exit non-zero) and not write output
    if python3 /app/solve.py "$bfile" "$out" >/dev/null 2>&1; then
      echo "malformed case accepted bad nan as valid"
      all_ok=0
    elif [ -f "$out" ]; then
      echo "malformed case wrote output despite failure"
      all_ok=0
    fi
  else
    if ! python3 /app/solve.py "$bfile" "$out" >/dev/null 2>&1; then
      echo "hidden case $name: solver did not run cleanly"
      all_ok=0
      continue
    fi
    g=$(gold_scan "$bfile") || { all_ok=0; continue; }
    if ! validate "$out" "$g" >/dev/null; then
      echo "hidden case $name failed validation"
      all_ok=0
    fi
  fi
done

if [ "$all_ok" -eq 1 ]; then
  reward=1
fi
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt