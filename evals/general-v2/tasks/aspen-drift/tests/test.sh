#!/bin/bash
# Verifier for aspen-drift: guards the supplied fixtures, validates that the
# visible snapshot /app/model.pt is a REAL trained state_dict at the exact
# layer nodes of the prescribed architecture, EXECUTES the deliverable scripts
# (/app/train_model.py, /app/evaluate.py) on the visible case and on every
# hidden case, and checks /app/predictions.txt. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_TRAIN_SHA="7f0461108434ebb84be60988e18f69d315ed8756c6d9dd88ca7f7c66907f73fa"
PRISTINE_HOLDOUT_SHA="ecb9a874cb82ac256699dc159a3acd1c29a1043c170b0c35f619b96e3e07673e"

guard_fail=0
check_sha() {
    local path="$1" want="$2" name="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $name missing" >&2
        guard_fail=1
        return
    fi
    local got
    got="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
        echo "no-modify: $name was modified" >&2
        guard_fail=1
    fi
}
check_sha /app/data/train.csv "$PRISTINE_TRAIN_SHA" "/app/data/train.csv"
check_sha /app/data/holdout.csv "$PRISTINE_HOLDOUT_SHA" "/app/data/holdout.csv"

python3 - "$guard_fail" <<'PY'
import csv, json, math, os, subprocess, sys

TRAINER = "/app/train_model.py"
EVAL = "/app/evaluate.py"
SNAP = "/app/model.pt"
PREDS = "/app/predictions.txt"
TRAIN_TOL = 0.15     # fit tolerance on a case's own training targets
HOLD_TOL = 0.35      # generalization tolerance on holdout targets
MAX_SNAP_BYTES = 20 * 1024 * 1024

failures = []
if int(sys.argv[1]):
    failures.append("supplied fixtures were modified or missing")

import torch


def build_model():
    return torch.nn.Sequential(
        torch.nn.Linear(6, 24),
        torch.nn.Tanh(),
        torch.nn.Linear(24, 1),
    )


def read_labeled(path):
    """Return (X, y) from a labeled CSV; y from the target column."""
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    X, y = [], []
    for r in rows:
        try:
            X.append([float(r[f"x{i}"]) for i in range(6)])
            y.append(float(r["target"]))
        except (KeyError, TypeError, ValueError) as e:
            raise ValueError(f"bad row: {e}")
    return X, y


def model_mae(model, X, y):
    with torch.no_grad():
        preds = model(torch.tensor(X, dtype=torch.float32)).squeeze(1).tolist()
    return sum(abs(p - t) for p, t in zip(preds, y)) / max(1, len(y))


def validate_snapshot(path, train_csv, tag):
    """A REAL trained snapshot: right keys/shapes, sane values, fits its data."""
    if not os.path.isfile(path):
        failures.append(f"{tag}: snapshot missing")
        return None
    size = os.path.getsize(path)
    if not (500 <= size <= MAX_SNAP_BYTES):
        failures.append(f"{tag}: snapshot size {size} out of bounds")
        return None
    try:
        state = torch.load(path, map_location="cpu", weights_only=True)
    except Exception as e:
        failures.append(f"{tag}: snapshot unloadable: {e}")
        return None
    if not isinstance(state, dict):
        failures.append(f"{tag}: snapshot is not a state_dict")
        return None
    want = {
        "0.weight": (24, 6), "0.bias": (24,),
        "2.weight": (1, 24), "2.bias": (1,),
    }
    if set(state.keys()) != set(want.keys()):
        failures.append(f"{tag}: keys {sorted(state.keys())} != expected node keys")
        return None
    for k, shape in want.items():
        t = state[k]
        if not torch.is_tensor(t) or tuple(t.shape) != shape:
            failures.append(f"{tag}: {k} wrong shape/type")
            return None
        if not torch.isfinite(t).all():
            failures.append(f"{tag}: {k} has non-finite values")
            return None
    if float(state["0.weight"].std()) == 0.0 or float(state["2.weight"].std()) == 0.0:
        failures.append(f"{tag}: degenerate (zero-variance) weights")
        return None
    try:
        model = build_model()
        model.load_state_dict(state)  # strict
        model.eval()
    except Exception as e:
        failures.append(f"{tag}: state_dict does not load strictly: {e}")
        return None
    try:
        X, y = read_labeled(train_csv)
    except Exception as e:
        failures.append(f"{tag}: cannot read {train_csv}: {e}")
        return None
    mae = model_mae(model, X, y)
    if not (mae <= TRAIN_TOL):
        failures.append(f"{tag}: not a real fit — train MAE {mae:.4f} > {TRAIN_TOL}")
        return None
    return model


def run(cmd, tag, timeout=240):
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout)
    except Exception as e:
        failures.append(f"{tag}: crashed: {e}")
        return None


# --- 1. visible snapshot /app/model.pt must be real and fit its data ---
if not os.path.isfile(TRAINER):
    failures.append("missing /app/train_model.py")
if not os.path.isfile(EVAL):
    failures.append("missing /app/evaluate.py")

if not failures:
    validate_snapshot(SNAP, "/app/data/train.csv", "visible snapshot")

    # --- 2. EXECUTE the trainer on the visible data ---
    out = "/tmp/aspen_recheck.pt"
    if os.path.exists(out):
        os.remove(out)
    r = run([sys.executable, TRAINER, "/app/data/train.csv", out], "trainer rerun")
    if r is not None:
        if r.returncode != 0:
            failures.append(f"trainer rerun rc={r.returncode}: {r.stderr[-300:]}")
        else:
            validate_snapshot(out, "/app/data/train.csv", "trainer rerun snapshot")

    # --- 3. EXECUTE the evaluator on the visible holdout ---
    pout = "/tmp/aspen_recheck_preds.txt"
    r = run([sys.executable, EVAL, "/app/data/holdout.csv", SNAP, pout],
            "evaluator rerun")
    true_targets = None
    with open("/app/data/holdout.csv", newline="") as fh:
        rows = list(csv.DictReader(fh))
    X = [[float(row[f"x{i}"]) for i in range(6)] for row in rows]
    # verifier-side ground truth for the visible holdout (same rule the data
    # was generated with)
    true_targets = [3.0 + 0.9 * x[0] + 1.4 * math.sin(1.3 * x[1])
                    + 0.5 * x[2] * x[2] - 0.7 * x[3] + 0.25 * x[4] * x[5]
                    for x in X]
    if r is None:
        pass
    elif r.returncode != 0:
        failures.append(f"evaluator rerun rc={r.returncode}: {r.stderr[-300:]}")
    else:
        try:
            got = [float(v) for v in r.stdout.split()]
            if len(got) != len(true_targets):
                failures.append("evaluator rerun: wrong line count on stdout")
            elif sum(abs(p - t) for p, t in zip(got, true_targets)) / len(got) > HOLD_TOL:
                failures.append("evaluator rerun: holdout MAE above tolerance")
        except ValueError as e:
            failures.append(f"evaluator rerun: unparseable stdout: {e}")

    # --- 4. visible deliverable /app/predictions.txt ---
    if not os.path.isfile(PREDS):
        failures.append("missing /app/predictions.txt")
    else:
        try:
            with open(PREDS) as fh:
                got = [float(v) for v in fh.read().split()]
            if len(got) != 200:
                failures.append(f"predictions.txt has {len(got)} lines, want 200")
            else:
                mae = sum(abs(p - t) for p, t in zip(got, true_targets)) / 200
                if mae > HOLD_TOL:
                    failures.append(f"predictions.txt MAE {mae:.4f} > {HOLD_TOL}")
        except ValueError as e:
            failures.append(f"predictions.txt unparseable: {e}")

# --- 5. hidden cases: genuinely distinct data, executed via the deliverables ---
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        train_csv = os.path.join(base, "train.csv")
        hold_csv = os.path.join(base, "holdout.csv")
        exp_path = os.path.join(base, "expected.json")
        if not (os.path.isfile(train_csv) and os.path.isfile(exp_path)):
            failures.append(f"hidden '{c}' malformed")
            continue
        if failures:
            continue  # already broken; avoid cascading noise
        try:
            with open(exp_path) as fh:
                exp = json.load(fh)
        except Exception as e:
            failures.append(f"hidden '{c}': unreadable expected: {e}")
            continue
        out = f"/tmp/aspen_hidden_{c}.pt"
        if os.path.exists(out):
            os.remove(out)
        r = run([sys.executable, TRAINER, train_csv, out], f"hidden '{c}' train")
        if r is None:
            continue
        if exp.get("mode") == "error":
            if r.returncode == 0:
                failures.append(f"hidden '{c}': trainer should fail on bad input")
            if os.path.exists(out):
                failures.append(f"hidden '{c}': trainer wrote a snapshot on bad input")
            continue
        if r.returncode != 0:
            failures.append(f"hidden '{c}': train rc={r.returncode}: {r.stderr[-300:]}")
            continue
        model = validate_snapshot(out, train_csv, f"hidden '{c}' snapshot")
        if model is None or not os.path.isfile(hold_csv):
            continue
        pout = f"/tmp/aspen_hidden_{c}_preds.txt"
        r = run([sys.executable, EVAL, hold_csv, out, pout], f"hidden '{c}' eval")
        if r is None:
            continue
        if r.returncode != 0:
            failures.append(f"hidden '{c}': eval rc={r.returncode}: {r.stderr[-300:]}")
            continue
        try:
            with open(pout) as fh:
                got = [float(v) for v in fh.read().split()]
            targets = [float(t) for t in exp["targets"]]
            if len(got) != len(targets):
                failures.append(f"hidden '{c}': wrong prediction count")
            else:
                mae = sum(abs(p - t) for p, t in zip(got, targets)) / len(targets)
                if mae > HOLD_TOL:
                    failures.append(f"hidden '{c}': holdout MAE {mae:.4f} > {HOLD_TOL}")
        except Exception as e:
            failures.append(f"hidden '{c}': eval output unparseable: {e}")
else:
    failures.append("hidden dir missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
