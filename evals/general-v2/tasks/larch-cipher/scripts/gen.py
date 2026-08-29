#!/usr/bin/env python3
"""Fixture generator for larch-cipher. Produces an underperforming CPU-classifier
scenario: a frozen-two-layer feature extractor plus a DESIGNATED OUTPUT LAYER that
was left frozen (requires_grad=False) and zero-initialised, so recorded training
signals show it stalled (loss flat, head gradient norm 0, val acc 0.5).

Usage: python3 gen.py <outdir> <case_id> <seed> [d] [h] [data_size] [flip]
Writes into outdir: meta.json base_state.pt training_signals.json plus
X_train.npy y_train.npy X_test.npy y_test.npy
"""
import json, os, sys
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


def make_net(d, h, out):
    class Net(nn.Module):
        def __init__(self, d, h, out):
            super().__init__()
            self.fc1 = nn.Linear(d, h)
            self.fc2 = nn.Linear(h, h)
            self.head = nn.Linear(h, out)
        def forward(self, x):
            x = F.relu(self.fc1(x))
            x = F.relu(self.fc2(x))
            return self.head(x)
    return Net(d, h, out)


def gen(outdir, case_id, seed, d=6, h=12, n_train=700, n_test=300, flip=0.12):
    g = np.random.default_rng(seed)
    # random strictly-separable boundary in input space
    w = g.normal(0.0, 1.0, (d,))
    w = w / (np.linalg.norm(w) + 1e-9)

    def build(n):
        X = g.normal(0.0, 1.0, (n, d)) * 1.5
        margin = X @ w
        y = np.where(margin >= 0.0, 1, 0).astype(np.int64)
        # label noise -> attainable ceiling ~ (1-flip)
        fl = g.random(n) < flip
        y[fl] = 1 - y[fl]
        return X.astype(np.float32), y

    X_tr, y_tr = build(n_train)
    X_te, y_te = build(n_test)

    torch.manual_seed(seed + 1)
    net = make_net(d, h, 2)
    net.eval()

    # Feature extractor: approximate a cheap affine lift so that when we then
    # freeze everything but the head, a linear head can still separate classes.
    with torch.no_grad():
        s = 0.9
        # fc1 : identity-ish embedding then relu (bias adds margin so nothing is clipped)
        M = np.zeros((h, d))
        M[:d, :d] = np.eye(d)
        net.fc1.weight.copy_(torch.tensor(M, dtype=torch.float32) * s)
        net.fc1.bias.copy_(torch.full((h,), 6.0))
        # fc2 : identity-ish on the first h dims
        M2 = np.eye(h) * s
        net.fc2.weight.copy_(torch.tensor(M2, dtype=torch.float32))
        net.fc2.bias.copy_(torch.zeros(h))
        # head: zeroed + frozen (the stall)
        net.head.weight.zero_()
        net.head.bias.zero_()

    meta = {
        "case_id": case_id,
        "seed": seed,
        "input_dim": d,
        "hidden_dim": h,
        "out_dim": 2,
        "freeze_prefixes": ["fc1.", "fc2.", "head."],  # provided base has ALL frozen
        "head_prefix": "head.",
        "head_frozen_in_base": True,
        "target_accuracy": 0.90,
    }

    try:
        os.makedirs(outdir, exist_ok=True)
        torch.save(net.state_dict(), os.path.join(outdir, "base_state.pt"))
        np.save(os.path.join(outdir, "X_train.npy"), X_tr)
        np.save(os.path.join(outdir, "y_train.npy"), y_tr)
        np.save(os.path.join(outdir, "X_test.npy"), X_te)
        np.save(os.path.join(outdir, "y_test.npy"), y_te)
        with open(os.path.join(outdir, "meta.json"), "w") as f:
            json.dump(meta, f, indent=2)

        # recorded training signals from the ORIGINAL (broken) run : head frozen
        sig = {
            "case_id": case_id,
            "device": "cpu",
            "optimizer": "expected optim.param_groups includes head params -> NONE got included",
            "per_epoch": [
                {"epoch": e, "train_loss": round(0.6931 + 1e-4 * e, 6),
                 "val_acc": 0.5, "head_grad_norm": 0.0} for e in range(1, 6)
            ],
            "final_state": "head.weight all zeros => softmax prob ~ [0.5,0.5] => acc stuck at 0.5",
            "symptom_note": "loss flat at ln2 for every epoch; head gradient norm 0.0 every step; "
                            "accuracy == chance. Inspect the module: the designated OUTPUT LAYER "
                            "(head) has requires_grad=False.",
        }
        with open(os.path.join(outdir, "training_signals.json"), "w") as f:
            json.dump(sig, f, indent=2)
        print("wrote", outdir, "d", d, "h", h, "reachable-ish acc ceiling ~", 1 - flip)
    except Exception as e:
        print("ERR", outdir, e)
        raise


if __name__ == "__main__":
    outdir, case_id, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    d, h, ntr, nte, flip = 6, 12, 900, 400, 0.05
    if len(sys.argv) > 4: d = int(sys.argv[4])
    if len(sys.argv) > 5: h = int(sys.argv[5])
    gen(outdir, case_id, seed, d, h, ntr, nte, flip)