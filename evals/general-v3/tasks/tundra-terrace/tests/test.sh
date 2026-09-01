#!/bin/bash
set -u
cd /app
PY=python3
R=1
fail(){ echo "FAIL: $1"; R=0; }

# ---------- delivery checks ----------
[ -f /app/reconstruct.py ] || fail "missing /app/reconstruct.py"
if ! $PY -m py_compile /app/reconstruct.py 2>/dev/null; then fail "engine does not compile"; fi
SZ=$(wc -c < /app/reconstruct.py)
if [ "$SZ" -gt 6000 ]; then fail "engine exceeds byte budget ($SZ > 6000)"; fi

# ---------- bring checkers into the container ----------
cat > /tmp/check_preds.py <<'PY'
import sys
pred = open(sys.argv[1]).read().splitlines()
exp  = open(sys.argv[2]).read().splitlines()
if pred[0].strip() != exp[0].strip():
    print("header mismatch:", pred[0], exp[0]); sys.exit(1)
p = [(int(a.split(',')[0]), float(a.split(',')[1])) for a in pred[1:] if a.strip()]
e = [(int(a.split(',')[0]), float(a.split(',')[1])) for a in exp[1:] if a.strip()]
if len(p) != len(e):
    print("row count mismatch", len(p), len(e)); sys.exit(1)
for (ps, pv), (es, ev) in zip(p, e):
    if ps != es:
        print("sid/order mismatch", ps, es); sys.exit(1)
    if not(-1000.0 < pv < 1000.0):
        print("score out of range", pv); sys.exit(1)
    if abs(pv - ev) > 2e-3:
        print("score out of tolerance %.6f vs %.6f" % (pv, ev)); sys.exit(1)
vals = [x[1] for x in p]
if len(set(round(x, 6) for x in vals)) < 2:
    print("predictions are uniform (not varying)"); sys.exit(1)
print("preds OK n=%d" % len(p))
PY
cat > /tmp/check_lowrank.py <<'PY'
import sys, json, numpy as np
z = np.load(sys.argv[1])
cfg = json.load(open(sys.argv[2]))
r = int(cfg['rank'])
keys = [k for k in z.files if k.endswith('_L')]
if len(keys) < 3:
    print("not enough low-rank matrices (%d)" % len(keys)); sys.exit(1)
for k in keys:
    base = k[:-2]
    Rname = base + '_R'
    if Rname not in z.files:
        print("missing", Rname); sys.exit(1)
    L = z[k]; Rt = z[Rname]
    if L.ndim != 2 or Rt.ndim != 2:
        print(base, "not 2D"); sys.exit(1)
    if L.shape[0] == 0 or L.shape[1] == 0:
        print(base, "empty"); sys.exit(1)
    M = L @ Rt
    sv = np.linalg.svd(M, compute_uv=False)
    nsig = int(np.sum(sv > 1e-4 * sv[0]))
    if not (1 <= nsig <= r):
        print(base, "significant singular values", nsig, "violates rank", r); sys.exit(1)
print("lowrank OK matrices=%d rank=%d" % (len(keys), r))
PY

# ---------- visible-case run on the fixtures ----------
rm -f /tmp/visible.csv /tmp/visible_lr.npz
if ! $PY /app/reconstruct.py /app/fixtures/model.json /app/fixtures/state.npz /app/fixtures/data.json \
        --out /tmp/visible.csv --lowrank /tmp/visible_lr.npz; then
    fail "visible-case engine run"
else
    $PY /tmp/check_preds.py /tmp/visible.csv /tests/expected_preds.csv || fail "visible-case predictions"
    $PY /tmp/check_lowrank.py /tmp/visible_lr.npz /app/fixtures/model.json || fail "visible-case low-rank"
fi

# ---------- deliverables left in /app ----------
[ -f /app/preds.csv ]   || fail "missing /app/preds.csv"
[ -f /app/lowrank.npz ] || fail "missing /app/lowrank.npz"
$PY /tmp/check_preds.py /app/preds.csv /tests/expected_preds.csv || fail "/app/preds.csv mismatch"
$PY /tmp/check_lowrank.py /app/lowrank.npz /app/fixtures/model.json || fail "/app/lowrank.npz invalid"

# ---------- hidden cases ----------
for d in /tests/hidden/case*/; do
  nm=$(basename "$d")
  mkdir -p /tmp/$nm && cp -r "$d" /tmp/$nm/src
  if ! $PY /app/reconstruct.py /tmp/$nm/src/model.json /tmp/$nm/src/state.npz /tmp/$nm/src/data.json \
        --out /tmp/$nm/out.csv --lowrank /tmp/$nm/lr.npz; then
      fail "$nm engine run"
      continue
  fi
  $PY /tmp/check_preds.py /tmp/$nm/out.csv /tmp/$nm/src/expected_preds.csv || fail "$nm predictions"
  $PY /tmp/check_lowrank.py /tmp/$nm/lr.npz /tmp/$nm/src/model.json || fail "$nm low-rank"
done

echo "$R" > /logs/verifier/reward.txt
echo "REWARD=$R"