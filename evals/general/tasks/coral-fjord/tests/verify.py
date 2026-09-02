#!/usr/bin/env python3
"""Verifier helper for coral-fjord.

  python3 /tests/verify.py <casedir> <artifacts_dir>

Validates one case:
  1. /app/pipeline.py is importable, exposes the documented API, and its
     forward pass keeps EVERY parameter connected to the graph: one
     forward/backward on the case's probe batch must leave a finite,
     non-zero gradient on every named parameter.
  2. The trained artifacts (model.pt, training_report.json) load, are
     consistent with the meta, and meet the loss/accuracy targets.
Prints "RESULT: PASS" on success.
"""
import importlib.util
import json
import os
import sys

import numpy as np
import torch
import torch.nn as nn

torch.set_num_threads(1)

PIPELINE_PATH = "/app/pipeline.py"


def fail(msg):
    print("VERIFY-FAIL: %s" % msg)
    sys.exit(1)


def load_pipeline(path=PIPELINE_PATH):
    try:
        spec = importlib.util.spec_from_file_location("pipeline", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:  # noqa: BLE001
        fail("cannot import %s: %r" % (path, e))


def main():
    case, out = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(case, "meta.json")))

    # ---- trained artifacts present -----------------------------------------
    for p in ("model.pt", "training_report.json"):
        if not os.path.isfile(os.path.join(out, p)):
            fail("missing artifact %s" % p)

    pipe = load_pipeline()
    model_cls = getattr(pipe, "SensorFusionModel", None)
    build = getattr(pipe, "build_model", None)
    if model_cls is None or build is None:
        fail("pipeline.py must expose SensorFusionModel and build_model")

    # ---- API smoke test on a fresh model ------------------------------------
    torch.manual_seed(int(meta["probe_seed"]))
    model = build(meta)
    if not isinstance(model, nn.Module):
        fail("build_model did not return an nn.Module")
    names = [n for n, _ in model.named_parameters()]
    for stage in ("encoder", "context", "gate", "head"):
        if not any(n.startswith(stage + ".") for n in names):
            fail("model is missing the %s stage parameters" % stage)

    px = torch.from_numpy(np.load(os.path.join(case, "probe_batch.npz"))["x"]).float()
    py = torch.from_numpy(np.load(os.path.join(case, "probe_batch.npz"))["y"]).long()
    logits = model(px)
    if logits.shape != (px.shape[0], int(meta["num_classes"])):
        fail("forward returned shape %s, expected %s"
             % (tuple(logits.shape), (px.shape[0], meta["num_classes"])))
    if not torch.isfinite(logits).all():
        fail("forward returned non-finite logits")

    # ---- CORE CHECK: full gradient flow through every stage -----------------
    model.zero_grad(set_to_none=True)
    loss = nn.functional.cross_entropy(model(px), py)
    loss.backward()
    bad = []
    for name, p in model.named_parameters():
        if p.grad is None:
            bad.append("%s:grad=None" % name)
        elif not torch.isfinite(p.grad).all():
            bad.append("%s:grad=nonfinite" % name)
        elif float(p.grad.norm()) <= 1e-8:
            bad.append("%s:grad=zero" % name)
    if bad:
        fail("gradient flow broken: %s" % ", ".join(bad))

    # ---- trained artifacts: load + consistency + targets --------------------
    state = torch.load(os.path.join(out, "model.pt"), map_location="cpu")
    if set(state.keys()) != set(names):
        fail("model.pt keys do not match the model's parameters")
    fresh = build(meta)
    fresh.load_state_dict(state)  # strict
    fresh.eval()

    Xte = torch.from_numpy(np.load(os.path.join(case, "test.npz"))["x"]).float()
    yte = np.load(os.path.join(case, "test.npz"))["y"]
    with torch.no_grad():
        acc = float((fresh(Xte).argmax(dim=1).numpy() == yte).mean())
    acc_target = float(meta["accuracy_target"])
    if acc < acc_target:
        fail("holdout accuracy %.4f < target %.4f" % (acc, acc_target))

    rep = json.load(open(os.path.join(out, "training_report.json")))
    for k in ("grad_norms", "all_params_have_gradients", "final_train_loss",
              "holdout_accuracy", "targets_met"):
        if k not in rep:
            fail("training_report.json missing key %s" % k)
    if not rep["all_params_have_gradients"]:
        fail("training_report says some parameter lacks gradients")
    gn = rep["grad_norms"]
    if set(gn.keys()) != set(names):
        fail("grad_norms keys %s != model parameters %s"
             % (sorted(gn.keys()), sorted(names)))
    for k, v in gn.items():
        if v is None or not np.isfinite(v) or v <= 1e-8:
            fail("grad_norms[%s] = %r is not a positive finite number"
                 % (k, v))
    if abs(float(rep["holdout_accuracy"]) - acc) > 5e-3:
        fail("training_report holdout accuracy %.4f != recomputed %.4f"
             % (float(rep["holdout_accuracy"]), acc))
    if float(rep["final_train_loss"]) > float(meta["loss_target"]) + 1e-9:
        fail("final_train_loss %.4f > loss_target %.4f"
             % (float(rep["final_train_loss"]), float(meta["loss_target"])))
    if bool(rep["targets_met"]) is not True:
        fail("training_report targets_met is not true")

    print("RESULT: PASS (grad flow ok; holdout acc %.4f >= %.2f; "
          "loss %.4f <= %.2f)"
          % (acc, acc_target, float(rep["final_train_loss"]),
             float(meta["loss_target"])))


if __name__ == "__main__":
    main()
