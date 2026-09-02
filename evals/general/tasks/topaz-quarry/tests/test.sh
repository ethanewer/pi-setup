#!/bin/bash
# Verifier for topaz-quarry: reloads the visible snapshot deliverable
# (/app/model.pt) into the exact configured architecture, validates the
# state_dict shape/finiteness/non-dummy constraints and held-out accuracy,
# then EXECUTES the deliverable /app/train.py on hidden runs (different
# input_dim/classes) and validates each produced snapshot the same way.
# Writes 1/0 to /logs/verifier/reward.txt. Never crashes on malformed output.
set -u

mkdir -p /logs/verifier
REWARD=0

python3 - <<'PY' && REWARD=1
import csv
import json
import math
import os
import subprocess
import sys

import torch
import torch.nn as nn

TRAIN = "/app/train.py"
failures = []


class Net(nn.Module):
    def __init__(self, input_dim, classes):
        super().__init__()
        self.fc = nn.Linear(input_dim, classes)

    def forward(self, x):
        return self.fc(x)


def load_eval(path, input_dim):
    feats, labels = [], []
    with open(path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            raise ValueError("empty CSV: %s" % path)
        cols = ["f%d" % j for j in range(input_dim)]
        for row in reader:
            feats.append([float(row[c]) for c in cols])
            labels.append(int(row["label"]))
    return torch.tensor(feats, dtype=torch.float32), torch.tensor(labels)


def check_snapshot(path, config, eval_csv, tag):
    if not os.path.isfile(path):
        failures.append("%s: snapshot missing" % tag)
        return
    if os.path.getsize(path) == 0:
        failures.append("%s: snapshot empty" % tag)
        return
    try:
        obj = torch.load(path, map_location="cpu")
    except Exception as e:
        failures.append("%s: torch.load failed: %s" % (tag, e))
        return
    if not isinstance(obj, dict):
        failures.append("%s: snapshot is not a state_dict dict" % tag)
        return
    D, C = int(config["input_dim"]), int(config["classes"])
    if set(obj.keys()) != {"fc.weight", "fc.bias"}:
        failures.append("%s: state_dict keys wrong: %r" % (tag, sorted(obj.keys())))
        return
    w, b = obj["fc.weight"], obj["fc.bias"]
    if not isinstance(w, torch.Tensor) or not isinstance(b, torch.Tensor):
        failures.append("%s: values are not tensors" % tag)
        return
    if tuple(w.shape) != (C, D) or tuple(b.shape) != (C,):
        failures.append("%s: shapes wrong: %r %r" % (tag, tuple(w.shape), tuple(b.shape)))
        return
    if not (torch.isfinite(w).all() and torch.isfinite(b).all()):
        failures.append("%s: non-finite weights" % tag)
        return
    if float(w.std()) <= 1e-6:
        failures.append("%s: dummy/constant weights (std too small)" % tag)
        return
    model = Net(D, C)
    try:
        model.load_state_dict(obj, strict=True)
    except Exception as e:
        failures.append("%s: strict reload failed: %s" % (tag, e))
        return
    model.eval()
    try:
        X, y = load_eval(eval_csv, D)
    except Exception as e:
        failures.append("%s: internal eval csv unreadable: %s" % (tag, e))
        return
    with torch.no_grad():
        pred = model(X).argmax(dim=1)
    acc = float((pred == y).float().mean())
    if acc < 0.90:
        failures.append("%s: eval accuracy %.4f < 0.90" % (tag, acc))
    else:
        print("%s: eval accuracy %.4f" % (tag, acc))


# --- visible deliverable ----------------------------------------------------
try:
    with open("/app/data/config.json", "r", encoding="utf-8") as fh:
        visible_cfg = json.load(fh)
except Exception as e:
    failures.append("config.json unreadable: %s" % e)
    visible_cfg = None

if visible_cfg is not None:
    if not os.path.isfile(TRAIN):
        failures.append("missing /app/train.py")
    else:
        check_snapshot("/app/model.pt", visible_cfg, "/app/data/eval.csv", "visible")

    # --- hidden generalization runs: execute the trainer -------------------
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden)
                       if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            train_csv = os.path.join(base, "train.csv")
            cfg_json = os.path.join(base, "config.json")
            eval_csv = os.path.join(base, "eval.csv")
            if not all(os.path.isfile(p) for p in (train_csv, cfg_json, eval_csv)):
                failures.append("hidden case %s malformed" % c)
                continue
            try:
                with open(cfg_json, "r", encoding="utf-8") as fh:
                    cfg = json.load(fh)
            except Exception as e:
                failures.append("hidden %s config unreadable: %s" % (c, e))
                continue
            out = "/tmp/tq_%s.pt" % c
            if os.path.exists(out):
                os.remove(out)
            try:
                r = subprocess.run([sys.executable, TRAIN, train_csv, cfg_json, out],
                                   capture_output=True, text=True, timeout=240)
            except Exception as e:
                failures.append("hidden %s: trainer crashed: %s" % (c, e))
                continue
            if r.returncode != 0:
                failures.append("hidden %s: trainer non-zero exit: %s"
                                % (c, r.stderr[-300:]))
                continue
            check_snapshot(out, cfg, eval_csv, "hidden-%s" % c)
    else:
        failures.append("no hidden case dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

echo "$REWARD" > /logs/verifier/reward.txt
exit 0
