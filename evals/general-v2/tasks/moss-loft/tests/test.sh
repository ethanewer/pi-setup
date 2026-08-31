#!/bin/bash
# Verifier for moss-loft. Executes the deliverable trainer on hidden
# (train, config, eval) cases, loads both the visible and freshly produced
# snapshots with torch, and checks: exact architecture shapes for the
# configured counts, genuine trained weights (finite, non-degenerate), and
# held-out accuracy >= threshold. Writes 0/1 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import subprocess
import sys

SOLVE = "/app/train.py"
VISIBLE_SNAPSHOT = "/app/model_snapshot.pt"
MIN_SIZE = 1024      # a real 6-tensor float32 snapshot is larger than this
MAX_SIZE = 50 * 1024 * 1024

failures = []


def check_snapshot(snapshot_path, config, eval_csv, min_acc, label):
    import torch
    import torch.nn as nn

    if not os.path.isfile(snapshot_path):
        failures.append("%s: snapshot missing" % label)
        return
    size = os.path.getsize(snapshot_path)
    if size < MIN_SIZE:
        failures.append("%s: snapshot suspiciously small (%d bytes)"
                        % (label, size))
        return
    if size > MAX_SIZE:
        failures.append("%s: snapshot oversized (%d bytes)" % (label, size))
        return
    try:
        sd = torch.load(snapshot_path, weights_only=True)
    except Exception as exc:
        failures.append("%s: torch.load failed: %r" % (label, exc))
        return
    if not isinstance(sd, dict):
        failures.append("%s: snapshot is not a state dict" % label)
        return

    d = int(config["input_dim"])
    h = int(config["hidden_units"])
    c = int(config["num_classes"])
    want = {
        "0.weight": (h, d), "0.bias": (h,),
        "2.weight": (h, h), "2.bias": (h,),
        "4.weight": (c, h), "4.bias": (c,),
    }
    if set(sd.keys()) != set(want.keys()):
        failures.append("%s: tensor keys %s != configured architecture %s"
                        % (label, sorted(sd.keys()), sorted(want.keys())))
        return
    for k, shape in want.items():
        if tuple(sd[k].shape) != shape:
            failures.append("%s: %s shape %s != %s"
                            % (label, k, tuple(sd[k].shape), shape))
            return
        if not torch.isfinite(sd[k]).all():
            failures.append("%s: %s contains non-finite values" % (label, k))
            return
        if float(sd[k].float().std()) <= 1e-7:
            failures.append("%s: %s degenerate (all-equal values)"
                            % (label, k))
            return

    model = nn.Sequential(
        nn.Linear(d, h), nn.ReLU(),
        nn.Linear(h, h), nn.ReLU(),
        nn.Linear(h, c),
    )
    try:
        model.load_state_dict(sd)
    except Exception as exc:
        failures.append("%s: load_state_dict failed: %r" % (label, exc))
        return
    model.eval()

    # score against the eval labels
    xs, ys = [], []
    try:
        import csv
        with open(eval_csv, newline="", encoding="utf-8") as fh:
            for rec in csv.DictReader(fh):
                xs.append([float(rec["x%d" % j]) for j in range(d)])
                ys.append(int(rec["label"]))
    except Exception as exc:
        failures.append("%s: eval csv unreadable: %r" % (label, exc))
        return
    if not xs:
        failures.append("%s: eval csv empty" % label)
        return
    with torch.no_grad():
        logits = model(torch.tensor(xs, dtype=torch.float32))
        acc = float((logits.argmax(dim=1)
                     == torch.tensor(ys)).float().mean())
    if acc < min_acc:
        failures.append("%s: accuracy %.4f < required %.4f (untrained/dummy "
                        "weights?)" % (label, acc, min_acc))


# ---------- 1. visible deliverables ----------
if not os.path.isfile(SOLVE):
    failures.append("missing /app/train.py")
if not os.path.isfile("/app/config.json"):
    failures.append("missing /app/config.json (visible fixture altered?)")

try:
    with open("/app/config.json") as fh:
        vis_cfg = json.load(fh)
except Exception as exc:
    failures.append("/app/config.json unreadable: %r" % (exc,))
    vis_cfg = None

if vis_cfg is not None:
    check_snapshot(VISIBLE_SNAPSHOT, vis_cfg, "/app/data/eval.csv",
                   0.85, "visible")

# ---------- 2. re-execute the trainer on hidden cases ----------
if os.path.isfile(SOLVE):
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d))) \
        if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        train_csv = os.path.join(base, "train.csv")
        cfg_path = os.path.join(base, "config.json")
        eval_csv = os.path.join(base, "eval.csv")
        exp_path = os.path.join(base, "expected.json")
        if not all(os.path.isfile(p) for p in
                   (train_csv, cfg_path, eval_csv, exp_path)):
            failures.append("hidden %s: malformed case" % case)
            continue
        try:
            with open(cfg_path) as fh:
                cfg = json.load(fh)
            with open(exp_path) as fh:
                min_acc = float(json.load(fh)["min_accuracy"])
        except Exception as exc:
            failures.append("hidden %s: unreadable config/expected: %r"
                            % (case, exc))
            continue
        out_pt = "/tmp/moss_loft_%s.pt" % case
        if os.path.exists(out_pt):
            os.remove(out_pt)
        try:
            r = subprocess.run(
                [sys.executable, SOLVE, train_csv, cfg_path, out_pt],
                capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            failures.append("hidden %s: train.py timed out" % case)
            continue
        if r.returncode != 0:
            failures.append("hidden %s: train.py exited %d: %s"
                            % (case, r.returncode, r.stderr[-300:]))
            continue
        check_snapshot(out_pt, cfg, eval_csv, min_acc, "hidden %s" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
