#!/usr/bin/env python3
"""Verifier for quill-fathom (executes-deliverable). Runs as root after the
agent; /tests is mounted read-only.

Checks, without trusting any pre-baked answers:
  * /app/adapt.py exists and references the fixed base path
    /app/base_snapshot.pt (the frozen checkpoint the contract requires).
  * /app/adapted_press.pt is a valid Linear(16->24), ReLU, Linear(24->3)
    state_dict, differs from the base checkpoint, and reaches accuracy >= 0.90
    on the visible fold.
  * Re-EXECUTES /app/adapt.py on the visible fold and on every hidden press
    fold; each run must exit 0, print finetune_accuracy=..., and yield a new
    valid snapshot that differs from base and reaches accuracy >= 0.90 on that
    fold's own labels (the base checkpoint alone is below 0.90 on these folds,
    so genuine adaptation is required).
  * Error contract: a fold missing the label column, and a header-only
    (zero-row) fold, must exit non-zero without producing a snapshot.
"""
import hashlib
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

APP = "/app"
HIDDEN = "/tests/hidden"
F, HID, C = 16, 24, 3
FEATS = ["x%d" % i for i in range(F)]
ADAPT_PY = "/app/adapt.py"
ART = "/app/adapted_press.pt"
BASE = "/app/base_snapshot.pt"
VISIBLE_FOLD = "/app/data/press_fold.csv"
ACC_TH = 0.90
CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + ((" | " + detail) if detail else ""))


def _try(fn, default="<err>"):
    try:
        return fn()
    except Exception as e:
        print("   ERR", repr(e)[:180])
        return default


def arch_ok(sd):
    """True iff sd is a 4-tensor state_dict implementing exactly
    Linear(16->24), ReLU, Linear(24->3), regardless of parameter naming."""
    if not isinstance(sd, dict) or len(sd) != 4:
        return False
    shapes = {tuple(v.shape) for v in sd.values()}
    return shapes == {(C,), (HID,), (HID, F), (C, HID)}


def load_net(path):
    sd = torch.load(path, map_location="cpu")
    if not arch_ok(sd):
        raise ValueError("state_dict is not a 16->24->3 two-Linear net")
    fresh = {}
    for k, v in sd.items():
        root = "0" if tuple(v.shape) in ((HID, F), (HID,)) else "2"
        suffix = ".weight" if k.endswith(".weight") else ".bias"
        fresh[root + suffix] = v
    net = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
    net.load_state_dict(fresh)
    net.eval()
    return net


def acc_of(path, csv_path):
    df = pd.read_csv(csv_path)
    X = torch.from_numpy(df[FEATS].to_numpy(dtype=np.float32))
    y = df["label"].to_numpy(dtype="int64")
    net = load_net(path)
    with torch.no_grad():
        pred = net(X).argmax(1).numpy()
    return float((pred == y).mean())


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def run_adapt(fold, out):
    return subprocess.run(["python3", ADAPT_PY, fold, out],
                          capture_output=True, text=True, timeout=240)


def main():
    base_ok = os.path.isfile(BASE)
    check("provided base checkpoint present", base_ok)
    base_sha = sha(BASE) if base_ok else ""
    if base_ok:
        ok = _try(lambda: arch_ok(torch.load(BASE, map_location="cpu")), False)
        check("base checkpoint has the required architecture", bool(ok))

    check("exists /app/adapt.py", os.path.isfile(ADAPT_PY))
    if os.path.isfile(ADAPT_PY):
        body = open(ADAPT_PY).read()
        check("adapt.py references the fixed base path /app/base_snapshot.pt",
              "/app/base_snapshot.pt" in body)

    # ---- visible artifact -------------------------------------------------
    art_ok = False
    if os.path.isfile(ART):
        a = _try(lambda: acc_of(ART, VISIBLE_FOLD), -1.0)
        changed = sha(ART) != base_sha
        art_ok = (isinstance(a, float) and a >= ACC_TH and changed)
        check("adapted_press.pt valid + differs from base + fold acc >= 0.90",
              art_ok, "acc=%.4f changed=%s" % (a, changed))
    else:
        check("exists /app/adapted_press.pt", False)

    # ---- re-execute on the visible fold ------------------------------------
    if os.path.isfile(ADAPT_PY) and base_ok:
        r = run_adapt(VISIBLE_FOLD, "/tmp/vis_adapt.pt")
        ok = r.returncode == 0 and os.path.isfile("/tmp/vis_adapt.pt")
        acc = _try(lambda: acc_of("/tmp/vis_adapt.pt", VISIBLE_FOLD), -1.0) if ok else -1.0
        changed = ok and sha("/tmp/vis_adapt.pt") != base_sha
        printed = r.stdout.strip().startswith("finetune_accuracy=")
        check("rerun on visible fold: rc0, finetune_accuracy=..., acc>=0.90, differs",
              ok and changed and acc >= ACC_TH and printed,
              "rc=%d acc=%.4f printed=%s" % (r.returncode, acc, printed))

    # ---- hidden folds -------------------------------------------------------
    if os.path.isdir(HIDDEN):
        folds = sorted(f for f in os.listdir(HIDDEN) if f.endswith(".csv"))
        check("hidden folds present", len(folds) >= 2, str(folds))
        for f in folds:
            fp = os.path.join(HIDDEN, f)
            out = "/tmp/h_%s.pt" % f
            if os.path.exists(out):
                os.remove(out)
            r = run_adapt(fp, out)
            ok = r.returncode == 0 and os.path.isfile(out)
            acc = _try(lambda: acc_of(out, fp), -1.0) if ok else -1.0
            changed = ok and sha(out) != base_sha
            check("hidden fold '%s' adapted to acc >= 0.90" % f,
                  ok and changed and acc >= ACC_TH,
                  "rc=%d acc=%.4f changed=%s" % (r.returncode, acc, changed))
    else:
        check("hidden folds directory present", False)

    # ---- error contract ------------------------------------------------------
    if os.path.isfile(ADAPT_PY):
        # (a) missing label column
        pd.DataFrame({"id": [1, 2], **{c: [0.1, 0.2] for c in FEATS}}).to_csv(
            "/tmp/nolabel.csv", index=False)
        r1 = run_adapt("/tmp/nolabel.csv", "/tmp/nolabel_out.pt")
        check("fold without label column exits non-zero",
              r1.returncode != 0 and not os.path.isfile("/tmp/nolabel_out.pt"),
              "rc=%d" % r1.returncode)
        # (b) zero data rows
        pd.DataFrame(columns=["id"] + FEATS + ["label"]).to_csv(
            "/tmp/empty.csv", index=False)
        r2 = run_adapt("/tmp/empty.csv", "/tmp/empty_out.pt")
        check("zero-row fold exits non-zero",
              r2.returncode != 0 and not os.path.isfile("/tmp/empty_out.pt"),
              "rc=%d" % r2.returncode)

    failed = sum(1 for _, ok in CHECKS if not ok)
    print("TOTAL %d FAILED %d" % (len(CHECKS), failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
