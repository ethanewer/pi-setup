#!/bin/bash
# Verifier for cinder-vane: EXECUTES the deliverable trainer (/app/train.py)
# with the standard config and with the Hydra debug-mode override on the
# visible fixture and on every hidden dataset under /tests/hidden. Checks the
# composed-config semantics (debug flag, 1-epoch/small-batch override, other
# defaults kept) and that written models genuinely reproduce their accuracy.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, subprocess, sys

TRAIN = "/app/train.py"
VISIBLE_CSV = "/app/data/readings.csv"
failures = []


def run_train(overrides):
    out_model = "/tmp/cv_model_%d.json" % abs(hash(tuple(overrides)))
    out_report = "/tmp/cv_report_%d.json" % abs(hash(tuple(overrides)))
    for p in (out_model, out_report):
        if os.path.exists(p):
            os.remove(p)
    args = ["python3", TRAIN] + list(overrides) + [
        "outputs.model=%s" % out_model, "outputs.report=%s" % out_report]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=180)
    except Exception as e:
        return None, None, "trainer crashed: %r" % (e,)
    if r.returncode != 0:
        return None, None, "trainer exited %d: %s" % (r.returncode, r.stderr[-400:])
    if not (os.path.isfile(out_model) and os.path.isfile(out_report)):
        return None, None, "trainer did not write outputs"
    try:
        with open(out_model) as f:
            model = json.load(f)
        with open(out_report) as f:
            report = json.load(f)
    except Exception as e:
        return None, None, "unreadable outputs: %r" % (e,)
    return model, report, None


def load_csv(path):
    X, y = [], []
    with open(path) as fh:
        header = fh.readline().strip().split(",")
        if header != ["vibration", "hours_since_service", "load", "needs_recal"]:
            raise ValueError("bad header in %s" % path)
        for line in fh:
            line = line.strip()
            if not line:
                continue
            a, b, c, t = line.split(",")
            X.append([float(a), float(b), float(c)])
            y.append(int(t))
    return X, y


def model_accuracy(model, csv):
    try:
        w = [float(v) for v in model["weights"]]
        b = float(model["bias"])
        if len(w) != 3 or model.get("n_features") != 3:
            return None
        X, y = load_csv(csv)
        hits = 0
        for row, t in zip(X, y):
            z = w[0]*row[0] + w[1]*row[1] + w[2]*row[2] + b
            p = 1.0 / (1.0 + (2.718281828459045 ** (-z)))
            hits += 1 if (1 if p > 0.5 else 0) == t else 0
        return hits / len(y)
    except Exception:
        return None


def close(a, b, tol=1e-6):
    try:
        return abs(float(a) - float(b)) <= tol
    except Exception:
        return False


# --- deliverables present ---------------------------------------------------
for d in ["/app/train.py", "/app/config.yaml", "/app/mode/standard.yaml",
          "/app/mode/debug.yaml", "/app/report.json", "/app/model.json",
          "/app/report_debug.json", "/app/model_debug.json"]:
    if not os.path.isfile(d):
        failures.append("missing deliverable %s" % d)
if failures:
    print("verify failures:", failures)
    sys.exit(1)

# mode group file contents (the override contract lives here)
for fname, expect in [
    ("standard", {"epochs": 40, "batch_size": 64, "debug": False}),
    ("debug", {"epochs": 1, "batch_size": 8, "debug": True,
               "outputs": {"model": "/app/model_debug.json",
                           "report": "/app/report_debug.json"}}),
]:
    try:
        import yaml
        with open("/app/mode/%s.yaml" % fname) as fh:
            got = yaml.safe_load(fh)
        for k, v in expect.items():
            if got.get(k) != v:
                failures.append("mode/%s.yaml has %s=%r (want %r)"
                                % (fname, k, got.get(k), v))
    except Exception as e:
        failures.append("mode/%s.yaml unreadable: %r" % (fname, e))

try:
    import yaml
    with open("/app/config.yaml") as fh:
        root = yaml.safe_load(fh)
    dl = root.get("defaults") or []
    has_mode = any((isinstance(e, dict) and "mode" in e) or e == "mode" for e in dl)
    if not has_mode:
        failures.append("config.yaml defaults list does not include the mode group")
    for k, v in [("dataset", "/app/data/readings.csv"), ("learning_rate", 0.05),
                 ("l2", 0.001), ("seed", 7)]:
        if root.get(k) != v:
            failures.append("config.yaml %s=%r (want %r)" % (k, root.get(k), v))
except Exception as e:
    failures.append("config.yaml unreadable: %r" % (e,))


def check_case(csv, label, floor):
    # --- standard run ---
    model, rep, err = run_train(["dataset=%s" % csv])
    if err:
        failures.append("%s standard: %s" % (label, err))
    else:
        n_rows = len(load_csv(csv)[1])
        if rep.get("debug") is not False:
            failures.append("%s standard: debug=%r (want False)" % (label, rep.get("debug")))
        if rep.get("epochs_effective") != 40 or rep.get("batch_size") != 64:
            failures.append("%s standard: epochs/batch = %r/%r (want 40/64)"
                            % (label, rep.get("epochs_effective"), rep.get("batch_size")))
        for k, v in [("learning_rate", 0.05), ("l2", 0.001), ("seed", 7)]:
            if not close(rep.get(k), v):
                failures.append("%s standard: %s=%r (want %r)" % (label, k, rep.get(k), v))
        if rep.get("dataset") != csv:
            failures.append("%s standard: dataset=%r (want %r)" % (label, rep.get("dataset"), csv))
        if rep.get("n_rows") != n_rows or rep.get("n_features") != 3:
            failures.append("%s standard: n_rows/n_features=%r/%r (want %d/3)"
                            % (label, rep.get("n_rows"), rep.get("n_features"), n_rows))
        acc = rep.get("accuracy")
        if not isinstance(acc, (int, float)) or acc < floor:
            failures.append("%s standard: accuracy=%r below floor %s" % (label, acc, floor))
        macc = model_accuracy(model, csv)
        if macc is None:
            failures.append("%s standard: model.json is not a valid 3-feature logistic model" % label)
        elif macc < floor:
            failures.append("%s standard: model reproduces accuracy %.3f < %s" % (label, macc, floor))

    # --- debug-mode override run ---
    model, rep, err = run_train(["mode=debug", "dataset=%s" % csv])
    if err:
        failures.append("%s debug: %s" % (label, err))
    else:
        if rep.get("debug") is not True:
            failures.append("%s debug: debug=%r (want True)" % (label, rep.get("debug")))
        if rep.get("epochs_effective") != 1:
            failures.append("%s debug: epochs_effective=%r (want 1)" % (label, rep.get("epochs_effective")))
        if rep.get("batch_size") != 8:
            failures.append("%s debug: batch_size=%r (want 8)" % (label, rep.get("batch_size")))
        # other defaults must be kept
        for k, v in [("learning_rate", 0.05), ("l2", 0.001), ("seed", 7)]:
            if not close(rep.get(k), v):
                failures.append("%s debug: default %s not kept (%r)" % (label, k, rep.get(k)))


# --- visible case -----------------------------------------------------------
check_case(VISIBLE_CSV, "visible", 0.75)

# visible deliverables were produced by a real default run
try:
    with open("/app/report.json") as fh:
        vis_rep = json.load(fh)
    if vis_rep.get("debug") is not False or vis_rep.get("epochs_effective") != 40 \
            or vis_rep.get("batch_size") != 64:
        failures.append("/app/report.json is not a standard-mode report: %r" % vis_rep)
    if not isinstance(vis_rep.get("accuracy"), (int, float)) or vis_rep["accuracy"] < 0.75:
        failures.append("/app/report.json accuracy below 0.75")
except Exception as e:
    failures.append("/app/report.json unreadable: %r" % (e,))
try:
    with open("/app/model.json") as fh:
        vis_model = json.load(fh)
    macc = model_accuracy(vis_model, VISIBLE_CSV)
    if macc is None or macc < 0.75:
        failures.append("/app/model.json invalid or accuracy %.3f < 0.75" % (macc or -1))
except Exception as e:
    failures.append("/app/model.json unreadable: %r" % (e,))

# visible debug deliverables were produced by a real mode=debug run
try:
    with open("/app/report_debug.json") as fh:
        dbg_rep = json.load(fh)
    if dbg_rep.get("debug") is not True or dbg_rep.get("epochs_effective") != 1 \
            or dbg_rep.get("batch_size") != 8:
        failures.append("/app/report_debug.json is not a debug-mode report: %r" % dbg_rep)
    for k, v in [("dataset", "/app/data/readings.csv"), ("learning_rate", 0.05),
                 ("l2", 0.001), ("seed", 7)]:
        if not close(dbg_rep.get(k), v) if k != "dataset" else dbg_rep.get(k) != v:
            failures.append("/app/report_debug.json default %s not kept (%r)" % (k, dbg_rep.get(k)))
    with open("/app/model_debug.json") as fh:
        dbg_model = json.load(fh)
    if not (isinstance(dbg_model.get("weights"), list)
            and len(dbg_model["weights"]) == 3 and dbg_model.get("n_features") == 3):
        failures.append("/app/model_debug.json is not a valid 3-feature model")
except Exception as e:
    failures.append("debug deliverables unreadable: %r" % (e,))

# a no-override debug run must not touch the standard-mode artifacts
try:
    import hashlib
    def sha(p):
        return hashlib.sha256(open(p, "rb").read()).hexdigest()
    before = (sha("/app/report.json"), sha("/app/model.json"))
    r = subprocess.run(["python3", "/app/train.py", "mode=debug"],
                       capture_output=True, text=True, timeout=180)
    after = (sha("/app/report.json"), sha("/app/model.json"))
    if r.returncode != 0:
        failures.append("no-override debug run exited %d: %s" % (r.returncode, r.stderr[-300:]))
    elif before != after:
        failures.append("mode=debug run modified /app/report.json or /app/model.json")
    elif not os.path.isfile("/app/report_debug.json"):
        failures.append("no-override debug run did not write /app/report_debug.json")
except Exception as e:
    failures.append("no-override debug check crashed: %r" % (e,))

# --- hidden cases -----------------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isfile(os.path.join(hidden_dir, d, "readings.csv")))
    if not cases:
        failures.append("no hidden cases found")
    for c in cases:
        check_case(os.path.join(hidden_dir, c, "readings.csv"), c, 0.70)
else:
    failures.append("missing /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
