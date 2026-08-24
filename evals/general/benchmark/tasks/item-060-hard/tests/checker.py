"""Objective verifier for item-060-hard.

Reward:
  1   - arch matches; freeze respected (all non-{last block, head} params
        bit-identical to pristine base); every allowed param changed; report
        consistent (correct config, exact trainable count for the
        last-block+head policy).
  0.5 - arch + freeze correct, but either the allowed params did not change
        enough through training, or report.json is missing/inconsistent.
  0   - wrong architecture, wrong freeze, or missing artifacts.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import torch

from model import TConfig, build_model

# The true hidden configuration (same constants the image build used).
CFG = TConfig(vocab_size=48, max_len=20, d_model=16, n_heads=4, n_layers=3, num_classes=4)
SEED = 13


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

    # architecture: keys + shapes must match exactly
    try:
        ref = build_model(CFG)
        ref.load_state_dict(fin, strict=True)
    except Exception:
        return 0
    if set(fin.keys()) != set(base.keys()):
        return 0

    last = f"blocks.{CFG.n_layers - 1}."
    allowed = ("blocks.%d." % (CFG.n_layers - 1), "head.")

    freeze_ok = True
    trained_changed = []  # every allowed param must change
    for k in base.keys():
        a, b = base[k], fin[k]
        if a.shape != b.shape:
            return 0
        if k.startswith(allowed):
            if not torch.equal(a, b):
                trained_changed.append(k)
        else:
            if not torch.equal(a, b):
                freeze_ok = False
    if not freeze_ok:
        return 0
    # every allowed param must actually have changed (all were trained)
    allowed_keys = [n for n in base.keys() if n.startswith(allowed)]
    if len(trained_changed) != len(allowed_keys):
        # at least one allowed param was NOT changed -> training incomplete
        return 0.5

    rp = "/app/output/report.json"
    if not os.path.exists(rp):
        return 0.5
    try:
        res = json.load(open(rp))
        cfg = res["config"]
        exp_cfg = {k: getattr(CFG, k) for k in
                   ("vocab_size", "max_len", "d_model", "n_heads", "n_layers", "num_classes")}
        total = sum(v.numel() for v in base.values())
        exp_trainable = sum(base[k].numel() for k in base.keys() if k.startswith(allowed))
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