#!/bin/bash
# Verifier for tide-grove: checks /app/train.py and the visible snapshot
# deliverable (/app/checkpoints/iter-120/model.pt + meta.json), then EXECUTES
# the deliverable trainer on the visible case and on every hidden case
# (different dims/iterations/hidden/lr/seed), verifying snapshot validity,
# learned accuracy on holdout, config-driven checkpoint node naming, and
# determinism. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

[ -f /app/train.py ] || fail "missing /app/train.py"
[ -f /app/checkpoints/iter-120/model.pt ] || fail "missing /app/checkpoints/iter-120/model.pt"
[ -f /app/checkpoints/iter-120/meta.json ] || fail "missing /app/checkpoints/iter-120/meta.json"

python3 - <<'PY'
import csv
import json
import math
import os
import re
import subprocess
import sys

import torch
import torch.nn as nn

TRAIN = "/app/train.py"
ACC_MIN = 0.85
failures = []


def parse_config(path):
    cfg = {}
    with open(path) as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            cfg[key.strip()] = value.strip()
    return {
        "iterations": int(cfg["iterations"]),
        "hidden": int(cfg["hidden"]),
        "lr": float(cfg["lr"]),
        "seed": int(cfg["seed"]),
    }


def read_xy(path):
    with open(path, newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        fidx = [i for i, n in enumerate(header) if n.startswith("x")]
        lidx = header.index("label")
        xs, ys = [], []
        for row in reader:
            if not row:
                continue
            xs.append([float(row[i]) for i in fidx])
            ys.append(int(row[lidx]))
    return torch.tensor(xs, dtype=torch.float32), torch.tensor(ys, dtype=torch.long), len(fidx)


def check_snapshot(snap_path, meta_path, train_csv, holdout_csv, cfg):
    if not os.path.isfile(snap_path):
        failures.append(f"missing snapshot {snap_path}")
        return
    size = os.path.getsize(snap_path)
    if size < 512:
        failures.append(f"snapshot {snap_path} suspiciously small ({size} bytes)")
    if size > 50 * 1024 * 1024:
        failures.append(f"snapshot {snap_path} oversized ({size} bytes)")
    try:
        sd = torch.load(snap_path, map_location="cpu", weights_only=True)
    except Exception as exc:
        failures.append(f"snapshot {snap_path} not loadable: {exc}")
        return
    if not isinstance(sd, dict):
        failures.append(f"snapshot {snap_path} is not a state_dict")
        return

    x, y, d = read_xy(train_csv)
    h = cfg["hidden"]
    if h != cfg["hidden"] or d <= 0:
        failures.append("bad dims")
        return

    def tensor_of(shapes):
        hits = [t for t in sd.values()
                if isinstance(t, torch.Tensor) and tuple(t.shape) in shapes]
        return hits

    w1s = tensor_of({(h, d)})
    b1s = tensor_of({(h,)})
    w2s = tensor_of({(2, h)})
    b2s = tensor_of({(2,)})
    if len(w1s) != 1 or len(b1s) != 1 or len(w2s) != 1 or len(b2s) != 1:
        failures.append(
            f"snapshot {snap_path} does not contain exactly the four tensors "
            f"of Linear({d},{h})+Linear({h},2) by shape")
        return
    w1, b1, w2, b2 = w1s[0], b1s[0], w2s[0], b2s[0]
    for name, t in (("w1", w1), ("b1", b1), ("w2", w2), ("b2", b2)):
        if not torch.isfinite(t).all():
            failures.append(f"snapshot {snap_path}: {name} has non-finite values")
            return
    for name, t in (("w1", w1), ("w2", w2)):
        if float(t.std()) <= 1e-8 or float(t.abs().max()) == 0.0:
            failures.append(f"snapshot {snap_path}: {name} is degenerate/untrained")
            return

    # meta.json must match the config and the data
    if os.path.isfile(meta_path):
        try:
            with open(meta_path) as fh:
                meta = json.load(fh)
            if set(meta.keys()) != {"iterations", "hidden", "lr", "seed", "feature_dim"}:
                failures.append(f"meta.json keys wrong: {sorted(meta.keys())}")
            elif (meta["iterations"] != cfg["iterations"] or meta["hidden"] != h
                  or abs(float(meta["lr"]) - cfg["lr"]) > 1e-9
                  or meta["seed"] != cfg["seed"] or meta["feature_dim"] != d):
                failures.append(f"meta.json does not match config/data: {meta}")
        except Exception as exc:
            failures.append(f"meta.json unreadable: {exc}")
    else:
        failures.append(f"missing meta.json at {meta_path}")

    # accuracy of the snapshot on train and holdout
    for tag, data, target in (("train", x, y), ("holdout",) + read_xy(holdout_csv)[:2]):
        net = nn.Sequential(nn.Linear(d, h), nn.ReLU(), nn.Linear(h, 2))
        sd_map = {
            "0.weight": w1, "0.bias": b1, "2.weight": w2, "2.bias": b2,
        }
        try:
            net.load_state_dict(sd_map)
        except Exception as exc:
            failures.append(f"cannot load snapshot into reference net: {exc}")
            return
        net.eval()
        with torch.no_grad():
            acc = float((net(data).argmax(dim=1) == target).float().mean())
        if acc < ACC_MIN:
            failures.append(
                f"snapshot {snap_path} accuracy on {tag} = {acc:.3f} < {ACC_MIN}")
        return_val = acc
    return


def run_trainer(train_csv, config_path, root):
    if os.path.isdir(root):
        subprocess.run(["rm", "-rf", root], check=True)
    r = subprocess.run([sys.executable, TRAIN, train_csv, config_path, root],
                       capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        failures.append(f"train.py exited {r.returncode} on {config_path}: {r.stderr[-400:]}")
        return None, None
    m = re.search(r"final_accuracy=([0-9.eE+-]+)\s*$", r.stdout)
    if not m:
        failures.append(f"train.py did not print final_accuracy for {config_path}")
        return None, None
    try:
        acc = float(m.group(1))
    except ValueError:
        failures.append("final_accuracy not parseable")
        return None, None
    if acc < ACC_MIN:
        failures.append(f"printed final_accuracy {acc:.3f} < {ACC_MIN} for {config_path}")
    cfg = parse_config(config_path)
    node = os.path.join(root, f"iter-{cfg['iterations']}")
    return os.path.join(node, "model.pt"), os.path.join(node, "meta.json")


def tensors_equal(a_path, b_path):
    try:
        a = torch.load(a_path, map_location="cpu", weights_only=True)
        b = torch.load(b_path, map_location="cpu", weights_only=True)
    except Exception as exc:
        failures.append(f"reload failed during determinism check: {exc}")
        return False
    if set(a.keys()) != set(b.keys()):
        return False
    return all(torch.equal(a[k], b[k]) for k in a)


# ---------- visible case ----------
cfg_v = parse_config("/app/train_config.txt")
snap_v, meta_v = run_trainer("/app/data/train.csv", "/app/train_config.txt", "/tmp/tg_verify_v1")
snap_v2, _ = run_trainer("/app/data/train.csv", "/app/train_config.txt", "/tmp/tg_verify_v2")
if snap_v and snap_v2:
    check_snapshot(snap_v, meta_v, "/app/data/train.csv", "/app/data/holdout.csv", cfg_v)
    if not tensors_equal(snap_v, snap_v2):
        failures.append("train.py is not deterministic on the visible case (two runs differ)")
    if os.path.isfile("/app/checkpoints/iter-120/model.pt") and not tensors_equal(
            "/app/checkpoints/iter-120/model.pt", snap_v):
        failures.append("delivered /app/checkpoints/iter-120/model.pt differs from a fresh run")
else:
    failures.append("visible run did not produce a snapshot")

# ---------- hidden cases ----------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        train_csv = os.path.join(base, "train.csv")
        hold_csv = os.path.join(base, "holdout.csv")
        cfg_path = os.path.join(base, "config.txt")
        if not all(os.path.isfile(p) for p in (train_csv, hold_csv, cfg_path)):
            failures.append(f"hidden case '{c}' malformed")
            continue
        cfg = parse_config(cfg_path)
        s1, m1 = run_trainer(train_csv, cfg_path, f"/tmp/tg_h1_{c}")
        s2, _ = run_trainer(train_csv, cfg_path, f"/tmp/tg_h2_{c}")
        if s1 and s2:
            check_snapshot(s1, m1, train_csv, hold_csv, cfg)
            if not tensors_equal(s1, s2):
                failures.append(f"hidden case '{c}': non-deterministic snapshots")
        else:
            failures.append(f"hidden case '{c}': no snapshot produced")
else:
    failures.append("no hidden case dir")

for f in failures:
    print("VERIFY-FAIL:", f, file=sys.stderr)
sys.exit(1 if failures else 0)
PY

[ $? -eq 0 ] || ok=0

echo "$ok" > /logs/verifier/reward.txt
exit 0
