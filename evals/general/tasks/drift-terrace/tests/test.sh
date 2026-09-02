#!/bin/bash
# drift-terrace verifier (executes-deliverable).
# Executes /app/train.py on the visible config and on every hidden case in
# /tests/hidden, loads the produced model + plain vector file, and checks
# the signed-coefficient constraint, parameter shape, held-out accuracy
# floor, debug one-epoch override and experiment-data artifacts.
set -u
mkdir -p /logs/verifier
R=1
fail(){ echo "FAIL: $1" >&2; R=0; }

# ---- required deliverables must exist ----
for f in /app/train.py /app/config.yaml /app/model.joblib /app/vector.out; do
  [ -f "$f" ] || fail "missing deliverable $f"
done
[ -f /app/experiment-data/progress.log ] || fail "missing /app/experiment-data/progress.log"

cat > /tmp/check_run.py <<'PY'
import sys, subprocess, os
import numpy as np, yaml, joblib, pandas as pd
from sklearn.model_selection import StratifiedKFold

TRAIN = sys.argv[1]
CFG = sys.argv[2]
OUT = sys.argv[3]
DO_FLOOR = bool(int(sys.argv[4]))
NEED_EPOCHS = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None

cfg = yaml.safe_load(open(CFG))
data_cfg = cfg["data"]
data_path = data_cfg["path"]
target_col = data_cfg["target_column"]
driver = cfg["optim"]["driver_feature"]
eps = float(cfg["optim"]["bound_epsilon"])
floor = float(cfg["evaluate"]["accuracy_floor"])
seed = int(cfg["split"]["seed"])
n_folds = int(cfg["split"]["n_folds"])
hold = int(cfg["split"]["held_out_fold"])

for p in (OUT, OUT + "_logs"):
    os.makedirs(p, exist_ok=True)
cmd = [TRAIN, "--config", CFG, "--out", OUT, "--logs", OUT + "_logs", "--data", data_path]
pr = subprocess.run(cmd, capture_output=True, text=True, cwd="/app")
if pr.returncode != 0:
    print("train.py exited %d: %s%s" % (pr.returncode, pr.stdout[-500:], pr.stderr[-500:])); sys.exit(1)

out = pr.stdout
if "SELFTEST" not in out or "MEAN_ACC" not in out:
    print("missing self-test tokens"); sys.exit(1)
ns = sum(1 for l in out.splitlines() if "SELFTEST" in l and "PASS" in l)
if ns < 2:
    print("too few PASS tokens"); sys.exit(1)
try:
    mean = float([l.split("MEAN_ACC=")[1] for l in out.splitlines() if "MEAN_ACC=" in l][0])
except Exception:
    print("MEAN_ACC not parseable"); sys.exit(1)
if not (0.0 <= mean <= 1.0):
    print("MEAN_ACC out of range"); sys.exit(1)

mf = os.path.join(OUT, cfg["output"]["model_file"])
vf = os.path.join(OUT, cfg["output"]["vector_file"])
pf = os.path.join(OUT + "_logs", cfg["output"].get("progress_file", "progress.log"))
if not (os.path.exists(mf) and os.path.exists(vf)):
    print("model/vector not produced"); sys.exit(1)
if not os.path.exists(pf):
    print("progress file not produced under experiment dir"); sys.exit(1)

art = joblib.load(mf)
feats = list(art.get("feature_names"))
coef = np.asarray(art["coef"], dtype=float)
itc = float(art["intercept"])
if coef.ndim != 1 or coef.shape[0] != len(feats):
    print("coef shape mismatch"); sys.exit(1)
if driver not in feats:
    print("driver feature %s not in feature_names" % driver); sys.exit(1)
k = coef[feats.index(driver)]
if not (k < -eps):
    print("driver coef not strictly negative: %f" % k); sys.exit(1)

vlines = [l.strip() for l in open(vf) if l.strip()]
try:
    cnt = int(vlines[0]); nums = [float(x) for x in vlines[1:]]
except Exception:
    print("vector.out not numeric"); sys.exit(1)
if cnt != len(coef) or len(nums) != len(coef) + 1:
    print("vector.out size mismatch"); sys.exit(1)
if not np.allclose(np.array(nums[:len(coef)]), coef, atol=1e-3):
    print("vector.out weights differ from model"); sys.exit(1)
if abs(nums[-1] - itc) > 1e-3:
    print("vector.out intercept differs from model"); sys.exit(1)

df = pd.read_csv(data_path)
drop = data_cfg.get("drop_columns", []) or []
if drop:
    df = df.drop(columns=[c for c in drop if c in df.columns])
X = np.nan_to_num(df[feats].to_numpy(dtype=float))
y = df[target_col].to_numpy().astype(float)
skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=seed)
folds = list(skf.split(X, y))
_, val = folds[hold]
pred = (X[val] @ coef + itc >= 0.0).astype(int)
acc = float(np.mean(pred == y[val]))
if DO_FLOOR and acc < floor:
    print("held-out accuracy %.4f < floor %.4f" % (acc, floor)); sys.exit(1)

if NEED_EPOCHS is not None:
    if ("epochs=%s" % NEED_EPOCHS) not in open(pf).read():
        print("debug epoch override missing epochs=%s" % NEED_EPOCHS); sys.exit(1)
print("ok acc=%.4f driver=%.4f epochs=%s" % (acc, k, NEED_EPOCHS or "-"))
PY

# ---- visible regenerate run ----
rm -rf /tmp/vis_out /tmp/vis_out_logs
if ! python3 /tmp/check_run.py /app/train.py /app/config.yaml /tmp/vis_out 1; then
  fail "visible regenerate"
fi

# ---- /app deliverables sanity ----
if [ "$R" = 1 ]; then
  python3 - <<'PY' || fail "app deliverable artifacts invalid"
import numpy as np, joblib
a = joblib.load("/app/model.joblib")
coef = np.asarray(a["coef"], dtype=float)
feats = list(a["feature_names"])
k = coef[feats.index(a["constrained_feature"])]
assert k < -1e-4, "deliverable /app/model.joblib driver coef not negative"
lines = [l for l in open("/app/vector.out") if l.strip()]
assert int(lines[0]) == len(coef), "deliverable /app/vector.out size mismatch"
print("app artifacts ok")
PY
fi

# ---- hidden cases ----
run_hidden(){
  local name="$1" cfg="$2" od="$3" floors="$4" epochs="${5:-}"
  rm -rf "$od" "$od"_logs
  if python3 /tmp/check_run.py /app/train.py "$cfg" "$od" "$floors" "$epochs" >/dev/null; then
    echo "hidden/$name ok"
  else
    fail "hidden/$name"
  fi
}
run_hidden h1 /tests/hidden/h1/config.yaml /tmp/rh1 1
run_hidden h2 /tests/hidden/h2/config.yaml /tmp/rh2 1
run_hidden h3 /tests/hidden/h3/config.yaml /tmp/rh3 0 1

echo "REWARD=$R"
echo "$R" > /logs/verifier/reward.txt
exit 0
