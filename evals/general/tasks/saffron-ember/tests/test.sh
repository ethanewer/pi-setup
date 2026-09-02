#!/bin/bash
# Verifier for saffron-ember (executes-deliverable): re-executes
# /app/finetune.py on the shipped fold and on hidden drifted folds, reloads
# every produced snapshot by shape, and checks the accuracy threshold, the
# base snapshot's integrity, and the documented error edge cases. Writes 1/0
# to /logs/verifier/reward.txt; never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

FT = "/app/finetune.py"
BASE = "/app/base_model.pt"
VISIBLE_FOLD = "/app/data/fold_a.csv"
VISIBLE_OUT = "/app/finetuned.pt"
ACC_TH = 0.90
DIM, HID, CLS = 16, 24, 3
failures = []


def fail(msg):
    failures.append(msg)


def check(cond, msg):
    if not cond:
        fail(msg)


def sha(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def arch_ok(sd):
    if not isinstance(sd, dict) or len(sd) != 4:
        return False
    shapes = {tuple(v.shape) for v in sd.values() if hasattr(v, "shape")}
    return shapes == {(CLS,), (HID,), (HID, DIM), (CLS, HID)}


def load_model(path):
    """Load any correctly-shaped 16->24->3 state_dict by tensor shape."""
    sd = torch.load(path, map_location="cpu")
    if not arch_ok(sd):
        raise ValueError("not a 16->24->3 two-Linear state_dict")
    fresh = {}
    for k, v in sd.items():
        s = tuple(v.shape)
        if s == (HID, DIM):
            fresh["0.weight"] = v
        elif s == (HID,):
            fresh["0.bias"] = v
        elif s == (CLS, HID):
            fresh["2.weight"] = v
        else:
            fresh["2.bias"] = v
    m = nn.Sequential(nn.Linear(DIM, HID), nn.ReLU(), nn.Linear(HID, CLS))
    m.load_state_dict(fresh)
    m.eval()
    return m


def fold_acc(snap_path, fold_csv):
    df = pd.read_csv(fold_csv)
    X = torch.tensor(df[[f"f{d}" for d in range(DIM)]].to_numpy(dtype=np.float32))
    y = torch.tensor(df["label"].to_numpy(dtype=np.int64))
    m = load_model(snap_path)
    with torch.no_grad():
        pred = m(X).argmax(1)
    return float((pred == y).float().mean())


def run_ft(fold, out, extra=()):
    try:
        return subprocess.run(
            [sys.executable, FT, fold, out, *extra],
            capture_output=True, text=True, timeout=240,
        )
    except Exception as exc:
        fail("finetune.py crashed on %s: %r" % (fold, exc))
        return None


def eval_run(tag, fold, out):
    r = run_ft(fold, out)
    if r is None or r.returncode != 0:
        fail("%s: finetune.py exited %s (%s)"
             % (tag, r.returncode if r else "?", (r.stderr[-200:] if r else "")))
        return
    if "finetune_accuracy=" not in (r.stdout or ""):
        fail("%s: no finetune_accuracy= line on stdout" % tag)
    if not os.path.isfile(out):
        fail("%s: no snapshot written" % tag)
        return
    try:
        acc = fold_acc(out, fold)
    except Exception as exc:
        fail("%s: snapshot unusable (%r)" % (tag, exc))
        return
    base_sd = torch.load(BASE, map_location="cpu")
    new_sd = torch.load(out, map_location="cpu")
    base_by_shape = {tuple(v.shape): v for v in base_sd.values()}
    changed = (arch_ok(new_sd) and len(base_by_shape) == 4 and any(
        not torch.equal(base_by_shape[tuple(v.shape)], v)
        for v in new_sd.values()))
    check(changed, "%s: snapshot is identical to the base (no adaptation)" % tag)
    check(acc >= ACC_TH, "%s: fold accuracy %.3f < %.2f" % (tag, acc, ACC_TH))
    print("  %s: acc=%.4f" % (tag, acc))


# ---- 1. deliverables exist --------------------------------------------------
check(os.path.isfile(FT), "missing /app/finetune.py")
check(os.path.isfile(VISIBLE_OUT), "missing /app/finetuned.pt")

# ---- 2. visible fold: re-run + score shipped artifact -----------------------
base_sha0 = sha(BASE)
if os.path.isfile(FT) and os.path.isfile(VISIBLE_FOLD) and base_sha0:
    eval_run("visible-rerun", VISIBLE_FOLD, "/tmp/ft_vis.pt")
    if os.path.isfile(VISIBLE_OUT):
        try:
            acc = fold_acc(VISIBLE_OUT, VISIBLE_FOLD)
            check(acc >= ACC_TH, "/app/finetuned.pt accuracy %.3f < %.2f"
                  % (acc, ACC_TH))
            print("  visible-artifact: acc=%.4f" % acc)
        except Exception as exc:
            fail("/app/finetuned.pt unusable (%r)" % exc)
    else:
        fail("missing /app/finetuned.pt")

# ---- 3. hidden drifted folds ------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fail("no hidden cases present")
    for i, case in enumerate(cases):
        fold = os.path.join(hidden_dir, case, "fold.csv")
        if not os.path.isfile(fold):
            fail("hidden '%s': missing fold.csv" % case)
            continue
        eval_run("hidden:%s" % case, fold, "/tmp/ft_h_%d.pt" % i)
else:
    fail("missing /tests/hidden")

# ---- 4. edge cases ----------------------------------------------------------
if os.path.isfile(FT):
    # no label column
    bad = "/tmp/no_label.csv"
    with open(bad, "w") as fh:
        fh.write("id," + ",".join("f%d" % d for d in range(DIM)) + "\n1,"
                 + ",".join("0.5" for _ in range(DIM)) + "\n")
    r = run_ft(bad, "/tmp/no_label.pt")
    check(r is not None and r.returncode != 0,
          "missing-label fold must exit non-zero")
    # zero data rows
    zed = "/tmp/zero_rows.csv"
    with open(zed, "w") as fh:
        fh.write("id," + ",".join("f%d" % d for d in range(DIM)) + ",label\n")
    r = run_ft(zed, "/tmp/zero.pt")
    check(r is not None and r.returncode != 0,
          "zero-row fold must exit non-zero")
    # non-numeric feature
    badn = "/tmp/bad_num.csv"
    with open(badn, "w") as fh:
        fh.write("id," + ",".join("f%d" % d for d in range(DIM)) + ",label\n1,"
                 + ",".join("0.5" for _ in range(DIM - 1)) + ",abc,0\n")
    r = run_ft(badn, "/tmp/badn.pt")
    check(r is not None and r.returncode != 0,
          "non-numeric feature must exit non-zero")
    # epochs cap
    r = run_ft(VISIBLE_FOLD, "/tmp/cap.pt", extra=["--epochs", "31"])
    check(r is not None and r.returncode != 0,
          "--epochs 31 must be refused")
    r = run_ft(VISIBLE_FOLD, "/tmp/one.pt", extra=["--epochs", "1"])
    check(r is not None and r.returncode == 0, "--epochs 1 must still run")

# ---- 5. base snapshot integrity ---------------------------------------------
if base_sha0:
    check(sha(BASE) == base_sha0, "/app/base_model.pt was modified")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
