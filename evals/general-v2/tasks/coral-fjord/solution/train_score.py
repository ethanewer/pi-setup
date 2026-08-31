#!/usr/bin/env python3
"""coral-fjord oracle trainer.

  python3 train_score.py <casedir> <outdir>    (defaults: /app/case /app)

Loads the (fixed) /app/pipeline.py, verifies that ONE forward/backward pass
populates a finite non-zero gradient on every parameter, trains the full
model to the case's loss/accuracy targets, and writes:
  <outdir>/model.pt            - trained state_dict
  <outdir>/training_report.json- grad norms, final loss, holdout accuracy
"""
import argparse
import importlib.util
import json
import os
import sys

import numpy as np
import torch
import torch.nn as nn

torch.set_num_threads(1)


def load_pipeline(path="/app/pipeline.py"):
    spec = importlib.util.spec_from_file_location("pipeline", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def grad_report(model, x, y):
    """One forward/backward; returns {name: grad_norm} and sanity flags."""
    model.zero_grad(set_to_none=True)
    logits = model(x)
    loss = nn.functional.cross_entropy(logits, y)
    loss.backward()
    report = {}
    ok = True
    for name, p in model.named_parameters():
        if p.grad is None:
            report[name] = None
            ok = False
            continue
        norm = float(p.grad.norm())
        report[name] = norm
        if not np.isfinite(norm) or norm <= 1e-8:
            ok = False
    return report, ok, float(loss.item())


@torch.no_grad()
def accuracy(model, x, y):
    model.eval()
    pred = model(x).argmax(dim=1)
    return float((pred == y).float().mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("casedir", nargs="?", default="/app/case")
    ap.add_argument("outdir", nargs="?", default="/app")
    args = ap.parse_args()
    case, outdir = args.casedir, args.outdir
    os.makedirs(outdir, exist_ok=True)

    meta = json.load(open(os.path.join(case, "meta.json")))
    torch.manual_seed(int(meta["seed"]))
    np.random.seed(int(meta["seed"]))

    pipeline = load_pipeline("/app/pipeline.py")
    model = pipeline.build_model(meta)

    Xtr = torch.from_numpy(np.load(os.path.join(case, "train.npz"))["x"]).float()
    ytr = torch.from_numpy(np.load(os.path.join(case, "train.npz"))["y"]).long()
    Xte = torch.from_numpy(np.load(os.path.join(case, "test.npz"))["x"]).float()
    yte = torch.from_numpy(np.load(os.path.join(case, "test.npz"))["y"]).long()
    px = torch.from_numpy(np.load(os.path.join(case, "probe_batch.npz"))["x"]).float()
    py = torch.from_numpy(np.load(os.path.join(case, "probe_batch.npz"))["y"]).long()

    # ---- gradient-flow audit BEFORE training -------------------------------
    report, grads_ok, probe_loss = grad_report(model, px, py)
    print("[grads] every-parameter flow ok = %s (probe loss %.4f)"
          % (grads_ok, probe_loss))
    if not grads_ok:
        print("[grads] FAILURE: some parameter has no/zero gradient; "
              "a stage is detached from the graph", file=sys.stderr)
        sys.exit(2)

    # ---- train the FULL model ----------------------------------------------
    opt = torch.optim.Adam(model.parameters(), lr=5e-3)
    model.train()
    final_loss = None
    for ep in range(int(meta.get("train_epochs_hint", 900))):
        opt.zero_grad()
        loss = nn.functional.cross_entropy(model(Xtr), ytr)
        loss.backward()
        opt.step()
        final_loss = float(loss.item())
        if ep % 200 == 0:
            print("[train] epoch %d loss %.4f" % (ep, final_loss))
    print("[train] final loss %.4f" % final_loss)

    holdout_acc = accuracy(model, Xte, yte)
    loss_target = float(meta["loss_target"])
    acc_target = float(meta["accuracy_target"])

    torch.save(model.state_dict(), os.path.join(outdir, "model.pt"))
    rep = {
        "case_id": meta["case_id"],
        "seed": meta["seed"],
        "grad_norms": report,
        "all_params_have_gradients": grads_ok,
        "final_train_loss": round(final_loss, 6),
        "holdout_accuracy": round(holdout_acc, 4),
        "loss_target": loss_target,
        "accuracy_target": acc_target,
        "targets_met": bool(final_loss <= loss_target
                            and holdout_acc >= acc_target),
    }
    with open(os.path.join(outdir, "training_report.json"), "w") as f:
        json.dump(rep, f, indent=2)
    print("[eval] holdout accuracy %.4f (target %.2f); targets_met=%s"
          % (holdout_acc, acc_target, rep["targets_met"]))
    if not rep["targets_met"]:
        sys.exit(3)


if __name__ == "__main__":
    main()
