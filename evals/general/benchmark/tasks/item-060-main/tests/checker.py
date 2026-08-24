"""Objective verifier for item-060-main.

Prints a reward in {1, 0.5, 0} to stdout:
  1   - architecture matches, freeze respected exactly (all non-head params are
        bit-identical to the pristine base checkpoint), head params actually
        changed through training, and report.json is consistent.
  0.5 - architecture + freeze are correct but either the head did not change
        (no real training) or report.json is missing/inconsistent.
  0   - anything else (wrong architecture, wrong freeze, missing artifacts).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import torch

from model import TConfig, build_model

# The true hidden configuration (same constants the image build used).
CFG = TConfig(vocab_size=32, max_len=16, d_model=8, n_heads=2, n_layers=2, num_classes=3)
SEED = 7


def load_any(path):
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except Exception:
        return torch.load(path, map_location="cpu")


def build_base_state():
    torch.manual_seed(SEED)
    m = build_model(CFG)
    return m.state_dict()


def reward():
    base = build_base_state()

    fps = "/app/output/finetuned.pt"
    if not os.path.exists(fps):
        return 0

    obj = load_any(fps)
    fin = obj.state_dict() if hasattr(obj, "state_dict") else dict(obj)

    # 1) architecture: keys + shapes must match the reference architecture exactly
    try:
        ref = build_model(CFG)
        ref.load_state_dict(fin, strict=True)
    except Exception:
        return 0
    if set(fin.keys()) != set(base.keys()):
        return 0

    # 2) freeze + training evidence
    freeze_ok = True
    head_changed = False
    for k in base.keys():
        a, b = base[k], fin[k]
        if a.shape != b.shape:
            return 0
        if k.startswith("head."):
            if not torch.equal(a, b):
                head_changed = True
        else:
            if not torch.equal(a, b):
                freeze_ok = False
    if not freeze_ok:
        return 0
    if not head_changed:
        return 0.5

    # 3) report consistency
    rp = "/app/output/report.json"
    if not os.path.exists(rp):
        return 0.5
    try:
        res = json.load(open(rp))
        cfg = res["config"]
        exp_cfg = {
            "vocab_size": CFG.vocab_size,
            "max_len": CFG.max_len,
            "d_model": CFG.d_model,
            "n_heads": CFG.n_heads,
            "n_layers": CFG.n_layers,
            "num_classes": CFG.num_classes,
        }
        exp_trainable = CFG.num_classes * CFG.d_model + CFG.num_classes
        total = sum(v.numel() for v in base.values())
        report_ok = (
            all(cfg.get(k) == v for k, v in exp_cfg.items())
            and res.get("trainable_params") == exp_trainable
            and res.get("frozen_params") == total - exp_trainable
            and isinstance(res.get("val_accuracy"), (int, float))
            and 0.0 <= float(res["val_accuracy"]) <= 1.0
        )
    except Exception:
        report_ok = False
    return 1 if report_ok else 0.5


print(reward())