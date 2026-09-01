#!/bin/bash
# Verifier for fennel-row: checks the visible experiment artifacts are real,
# then EXECUTES /app/train.py on hidden datasets/configs and verifies the run
# wrote its artifacts under the exact experiment directory named in the hidden
# config. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, math, os, subprocess, sys

failures = []

def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)

def check_artifacts(exp_dir, cfg, tag):
    if not os.path.isdir(exp_dir):
        failures.append("%s: experiment dir %s missing" % (tag, exp_dir))
        return
    cfg_copy_path = os.path.join(exp_dir, "config.json")
    prog_path = os.path.join(exp_dir, "progress.json")
    for p in (cfg_copy_path, prog_path):
        if not os.path.isfile(p) or os.path.getsize(p) == 0:
            failures.append("%s: %s missing or empty" % (tag, p))
    if failures:
        return
    try:
        eff = load_json(cfg_copy_path)
    except Exception as e:
        failures.append("%s: config.json unreadable: %r" % (tag, e))
        return
    if eff.get("paths", {}).get("experiment") != cfg["paths"]["experiment"]:
        failures.append("%s: experiment config copy does not match input config" % tag)
    if eff.get("training") != cfg.get("training"):
        failures.append("%s: experiment config training block mismatch" % tag)
    try:
        prog = load_json(prog_path)
    except Exception as e:
        failures.append("%s: progress.json unreadable: %r" % (tag, e))
        return
    epochs = int(cfg["training"]["epochs"])
    if not isinstance(prog, list) or len(prog) != epochs:
        failures.append("%s: progress.json len %r != epochs %d"
                        % (tag, len(prog) if isinstance(prog, list) else "?", epochs))
        return
    if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in prog):
        failures.append("%s: progress.json has non-finite/non-numeric losses" % tag)
        return
    if prog[-1] >= prog[0]:
        failures.append("%s: loss did not decrease (%.4f -> %.4f)" % (tag, prog[0], prog[-1]))
    # model artifact
    model_path = cfg["paths"]["model"]
    if not os.path.isfile(model_path) or os.path.getsize(model_path) == 0:
        failures.append("%s: model %s missing or empty" % (tag, model_path))
        return
    try:
        model = load_json(model_path)
    except Exception as e:
        failures.append("%s: model unreadable: %r" % (tag, e))
        return
    if int(model.get("epochs", -1)) != epochs:
        failures.append("%s: model epochs mismatch" % tag)
    if not isinstance(model.get("weights"), list) or not model["weights"]:
        failures.append("%s: model weights missing" % tag)

# no-modify on visible fixtures
import hashlib
if not os.path.isfile("/app/train.py"):
    failures.append("missing /app/train.py")
if not os.path.isfile("/app/config.json"):
    failures.append("missing /app/config.json")
if not os.path.isfile("/app/model.json"):
    failures.append("missing /app/model.json (visible run artifact)")
if not os.path.isfile("/app/data/orchard.csv"):
    failures.append("no-modify: /app/data/orchard.csv missing")
if not os.path.isfile("/app/experiments/frost-29/seed-5/config.json"):
    failures.append("visible: /app/experiments/frost-29/seed-5/config.json missing")
if not os.path.isfile("/app/experiments/frost-29/seed-5/progress.json"):
    failures.append("visible: /app/experiments/frost-29/seed-5/progress.json missing")

if not os.path.isfile("/app/train.py"):
    failures.append("missing /app/train.py (duplicate guard)")
else:
    # visible artifacts
    if os.path.isfile("/app/config.json"):
        try:
            vis_cfg = load_json("/app/config.json")
            check_artifacts(vis_cfg["paths"]["experiment"], vis_cfg, "visible")
        except Exception as e:
            failures.append("visible check raised %r" % e)

    # hidden cases: copy data, run trainer with hidden config, verify artifacts
    hidden_dir = "/tests/hidden"
    for case in sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []:
        base = os.path.join(hidden_dir, case)
        cfg_path = os.path.join(base, "config.json")
        if not os.path.isfile(cfg_path):
            failures.append("hidden %r: no config.json" % case)
            continue
        try:
            cfg = load_json(cfg_path)
        except Exception as e:
            failures.append("hidden %r: bad config: %r" % (case, e))
            continue
        # copy the hidden dataset into /app/data under a case-scoped name
        import glob
        csvs = [p for p in glob.glob(os.path.join(base, "*.csv"))]
        if not csvs:
            failures.append("hidden %r: no csv fixture" % case)
            continue
        src = csvs[0]
        dst = os.path.join("/app/data", "hidden_%s_%s" % (case, os.path.basename(src)))
        try:
            with open(src, "rb") as fi, open(dst, "wb") as fo:
                fo.write(fi.read())
        except Exception as e:
            failures.append("hidden %r: cannot stage dataset: %r" % (case, e))
            continue
        eff_cfg = json.loads(json.dumps(cfg))
        eff_cfg["paths"]["dataset"] = dst
        staged_cfg = "/tmp/fennel_cfg_%s.json" % case
        with open(staged_cfg, "w", encoding="utf-8") as fh:
            json.dump(eff_cfg, fh)
        # clean the expected experiment dir to prove the run creates it
        exp_dir = eff_cfg["paths"]["experiment"]
        subprocess.run(["rm", "-rf", exp_dir], check=False)
        try:
            r = subprocess.run([sys.executable, "/app/train.py", "--config", staged_cfg],
                               capture_output=True, text=True, timeout=240)
        except subprocess.TimeoutExpired:
            failures.append("hidden %r: train.py timed out" % case)
            continue
        if r.returncode != 0:
            failures.append("hidden %r: train.py failed rc=%s err=%.300s"
                            % (case, r.returncode, r.stderr))
            continue
        check_artifacts(exp_dir, eff_cfg, "hidden/%s" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
