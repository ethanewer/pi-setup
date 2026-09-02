#!/bin/bash
# Oracle for quartz-marsh: write the init program, then RUN it with defaults on
# the shipped config to produce /app/model_pack.pt and /app/init_report.json.
# Never reads /tests.
set -eu

cat > /app/init_model.py <<'PY'
#!/usr/bin/env python3
"""Initialize Quartz Marsh instance encoder + bag classifier within budget."""
import argparse
import json
import math
import os
import sys

import torch
import torch.nn as nn


class MarshNet(nn.Module):
    def __init__(self, feature_dim, hidden_dim, num_classes):
        super().__init__()
        self.instance_encoder = nn.Linear(feature_dim, hidden_dim)
        self.bag_classifier = nn.Linear(hidden_dim, num_classes)


def pick_hidden(f, c, lo, hi):
    """Smallest H with lo <= H*(f+c+1)+c <= hi; returns None if impossible."""
    a = f + c + 1
    h = max(1, math.ceil((lo - c) / a))
    while a * h + c <= hi:
        if a * h + c >= lo:
            return h
        h += 1
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/app/config.json")
    ap.add_argument("--model-out", default="/app/model_pack.pt")
    ap.add_argument("--report-out", default="/app/init_report.json")
    args = ap.parse_args()

    with open(args.config, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    f = int(cfg["feature_dim"])
    c = int(cfg["num_classes"])
    lo = int(cfg["min_params"])
    hi = int(cfg["max_params"])
    seed = int(cfg.get("seed", 0))

    h = pick_hidden(f, c, lo, hi)
    if h is None:
        raise SystemExit("no hidden width satisfies the budget")

    torch.manual_seed(seed)
    model = MarshNet(f, h, c)
    for p in model.parameters():
        nn.init.normal_(p, mean=0.0, std=0.05)

    finite = all(torch.isfinite(p).all().item() for p in model.parameters())
    state = model.state_dict()
    param_count = sum(int(t.numel()) for t in state.values())

    os.makedirs(os.path.dirname(os.path.abspath(args.model_out)), exist_ok=True)
    torch.save(state, args.model_out)

    report = {
        "feature_dim": f,
        "num_classes": c,
        "hidden_dim": h,
        "param_count": param_count,
        "min_params": lo,
        "max_params": hi,
        "init_ok": bool(finite and param_count > 0),
        "within_budget": bool(lo <= param_count <= hi),
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.report_out)), exist_ok=True)
    with open(args.report_out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print("hidden_dim=%d param_count=%d" % (h, param_count))


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/init_model.py

python3 /app/init_model.py

echo "solve.sh done"
ls -l /app/init_model.py /app/model_pack.pt /app/init_report.json
cat /app/init_report.json
