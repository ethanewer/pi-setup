#!/usr/bin/env python3
"""Verifier for umber-vault (executes-deliverable). Runs as root after the agent;
/tests is mounted read-only.

Re-executes every deliverable and checks behaviour, not just presence:
  * split.py -> deterministic byte-identical partitions, matching an independent
    canonical reference, pairwise-disjoint, covering every id (incl. tiny edge).
  * train.py -> reproduces the documented 48->64->2 net + solver and writes a
    real snapshot reaching train accuracy >= 0.90.
  * finetune.py -> reloads the base snapshot, adapts to a different hidden fold
    (valid new checkpoint that differs from base, fold accuracy >= 0.90).
  * predict.py -> emits EXACTLY one digit per row to stdout AND the result file,
    both equal to a reloaded-snapshot recompute (provided + hidden rows); format
    errors exit non-zero.
  * bag mode -> per-bag majority scores match an independent streamed recompute
    (provided, hidden, and a 1.2M-patch stress bag) with bounded RSS and within
    a wall-clock deadline.
"""
import hashlib
import os
import random
import resource
import subprocess
import sys
import time

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

APP = "/app"
HIDDEN = "/tests/hidden"
F, HID, OUT = 48, 64, 2
FEAT_COLS = [f"x{i}" for i in range(F)]
SPLIT_SEED = 20250531
SPLIT_PY = "/app/split.py"
TRAIN_PY = "/app/train.py"
BASE = "/app/model_snapshot.pt"
FINETUNE_PY = "/app/finetune.py"
PREDICT_PY = "/app/predict.py"
PRED_LABELS = "/app/pred_labels.txt"
BAG_SCORES = "/app/large_bag_scores.txt"
TRAIN_ACC_TH = 0.90
FINETUNE_ACC_TH = 0.90
BAG_RSS_CAP_KB = 400_000
BAG_TIME_MAX_S = 120.0
STRESS_ROWS = 1_200_000
CHECKS = []


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(F, HID)
        self.l2 = nn.Linear(HID, OUT)

    def forward(self, x):
        return self.l2(NF.relu(self.l1(x)))


def _try(fn, default="<err>"):
    try:
        return fn()
    except Exception as e:
        print("   ERR", repr(e)[:180])
        return default


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + ((" | " + detail) if detail else ""))


def arch_ok(sd):
    """True iff sd is a 4-tensor state_dict implementing exactly
    Linear(48->64), ReLU, Linear(64->2) -- regardless of parameter naming
    (Sequential '0.*'/'2.*', named modules, plain attributes, ...). The two
    Linear layers are identified by their distinctive shapes (64,48) and (2,64).
    """
    if not isinstance(sd, dict) or len(sd) != 4:
        return False
    n_w = sum(1 for k in sd if k.endswith(".weight"))
    n_b = sum(1 for k in sd if k.endswith(".bias"))
    if n_w != 2 or n_b != 2:
        return False
    shapes = {tuple(v.shape) for v in sd.values()}
    return shapes == {(OUT,), (HID,), (HID, F), (OUT, HID)}


def load_model(path=BASE):
    """Load any correctly-shaped 48->64->2 two-Linear state_dict, remapping
    arbitrary parameter names onto the reference layout by tensor shape."""
    sd = torch.load(path, map_location="cpu")
    if not arch_ok(sd):
        raise ValueError("state_dict is not a 48->64->2 two-Linear net")
    fresh = {}
    for k, v in sd.items():
        root = "l1" if v.shape in ((HID, F), (HID,)) else "l2"
        suffix = ".weight" if k.endswith(".weight") else ".bias"
        fresh[root + suffix] = v
    m = Net()
    m.load_state_dict(fresh)
    m.eval()
    return m


def model_labels(model, X):
    with torch.no_grad():
        return model(torch.from_numpy(X)).argmax(1).cpu().numpy()


def labels_text(m, X):
    return "".join(f"{int(v)}\n" for v in model_labels(m, X))


def snap_of(path, csv_path):
    """Accuracy of a snapshot state_dict on a labeled CSV."""
    df = pd.read_csv(csv_path)
    X = df[FEAT_COLS].to_numpy(dtype=np.float32)
    y = df["label"].to_numpy(dtype=np.int64)
    m = load_model(path)
    pred = model_labels(m, X)
    return float((pred == y).mean())


def bag_reference(m, path):
    tally, order = {}, []
    for chunk in pd.read_csv(path, chunksize=4096):
        X = chunk[FEAT_COLS].to_numpy(dtype=np.float32)
        bids = chunk["bag_id"].to_numpy().astype(np.int64)
        labs = model_labels(m, X)
        for b, lab in zip(bids, labs):
            bb = int(b)
            if bb not in tally:
                tally[bb] = [0, 0]
                order.append(bb)
            tally[bb][int(lab)] += 1
    out = []
    for b in order:
        c = tally[b]
        out.append(1 if c[1] > c[0] else 0)
    return "".join(f"{v}\n" for v in out)


def split_reference(df):
    df = df.sort_values("id").reset_index(drop=True)
    n = len(df)
    idx = list(range(n))
    random.Random(SPLIT_SEED).shuffle(idx)
    ntr = round(n * 0.7)
    nval = round(n * 0.15)
    return {
        "train": df.iloc[idx[0:ntr]],
        "val": df.iloc[idx[ntr:ntr + nval]],
        "test": df.iloc[idx[ntr + nval:]],
    }


def write_split(frames, prefix):
    for k, df in frames.items():
        df.reset_index(drop=True).to_csv(f"{prefix}_{k}.csv", index=False)


def sig(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def run(cmds):
    return subprocess.run(cmds, capture_output=True, text=True)


def check_partition(prefix, full_ids):
    parts = {k: set(pd.read_csv(f"{prefix}_{k}.csv")["id"].astype(int))
             for k in ("train", "val", "test")}
    union = set().union(*parts.values())
    total = sum(len(v) for v in parts.values())
    disjoint = total == len(union)
    cover = union == full_ids
    return {
        "disjoint": disjoint, "cover": cover, "total": total,
        "counts": {k: len(v) for k, v in parts.items()},
    }


def _run_recording(cmds):
    """Run a child and also return (maxrss_kb, wall_s) using child accounting."""
    t0 = time.monotonic()
    p = subprocess.run(cmds, capture_output=True, text=True)
    dt = time.monotonic() - t0
    rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return p.returncode, p.stdout, p.stderr, rss, dt


def _measure_bag(bag, out_path):
    """Run bag predict once under a child that polls the predictor's VmHWM.
    Returns (rc, peak_kb, seconds). Independent of this (potentially large)
    verifier process because the predictor runs as a grandchild of a tiny
    dedicated wrapper."""
    p = subprocess.run([sys.executable, "/tests/bag_wrap.py", bag, out_path],
                       capture_output=True, text=True)
    for line in p.stdout.splitlines():
        parts = line.split()
        if len(parts) == 4 and parts[0] == "MEAS":
            return int(parts[1]), int(parts[2]), float(parts[3])
    print("  MEAS-wrapper no MEAS line; stdout=", p.stdout[:200],
          " stderr=", p.stderr[-300:])
    return -1, 0, -1.0



def _write_stress_bag(path, rows):
    n = rows - (rows % 4)
    rng = np.random.default_rng(99)
    bg = np.repeat(np.arange(4), n // 4)
    feats = rng.uniform(-1.0, 1.0, (n, F))
    df = pd.DataFrame(feats, columns=FEAT_COLS)
    df.insert(0, "bag_id", bg)
    df.to_csv(path, index=False)
    return True


def main():
    for f in ["split.py", "predict.py", "finetune.py", "train.py",
              "model_snapshot.pt", "pred_labels.txt", "large_bag_scores.txt"]:
        check(f"exists /app/{f}", os.path.isfile(f"{APP}/{f}"))
    for k in ("train", "val", "test"):
        check(f"exists /app/split_{k}.csv", os.path.isfile(f"{APP}/split_{k}.csv"))

    # ---- snapshot sanity -------------------------------------------------
    model = None
    if os.path.isfile(BASE):
        got = _try(lambda: (os.path.getsize(BASE),
                            torch.load(BASE, map_location="cpu")))
        ok = (isinstance(got, tuple) and got[0] > 2000 and
              isinstance(got[1], dict) and arch_ok(got[1]))
        check("snapshot valid 48->64->2 state_dict (any param names)",
              ok, repr(list(got[1].keys())) if isinstance(got, tuple) and isinstance(got[1], dict) else repr(got))
        model = _try(lambda: load_model(BASE))

    # ================= 1. split determinism + canonical + coverage ============
    main_df = _try(lambda: pd.read_csv(f"{APP}/data/dataset.csv"))
    if os.path.isfile(f"{APP}/split.py") and isinstance(main_df, pd.DataFrame):
        r1 = run(["python3", SPLIT_PY, f"{APP}/data/dataset.csv", "/tmp/sa"])
        r2 = run(["python3", SPLIT_PY, f"{APP}/data/dataset.csv", "/tmp/sb"])
        det = all(os.path.isfile(f"/tmp/sa_{k}.csv") and os.path.isfile(f"/tmp/sb_{k}.csv")
                  and sig(f"/tmp/sa_{k}.csv") == sig(f"/tmp/sb_{k}.csv")
                  for k in ("train", "val", "test"))
        check("split.py deterministic across invocations", det and r1.returncode == 0,
              r1.stdout.strip())
        write_split(split_reference(main_df), "/tmp/can")
        canon = all(
            os.path.isfile(f"/tmp/sa_{k}.csv") and
            pd.read_csv(f"/tmp/sa_{k}.csv").equals(
                pd.read_csv(f"/tmp/can_{k}.csv"))
            for k in ("train", "val", "test"))
        check("split.py == canonical reference", canon)

    if isinstance(main_df, pd.DataFrame):
        full_ids = set(main_df["id"].astype(int))
        ok_files = all(os.path.isfile(f"{APP}/split_{k}.csv")
                       for k in ("train", "val", "test"))
        if ok_files:
            part = _try(lambda: check_partition(f"{APP}/split", full_ids), {})
            props = part.get("counts", {})
            n = len(full_ids)
            props_ok = (props.get("train", -1) == round(n * 0.7) and
                        props.get("val", -1) == round(n * 0.15) and
                        props.get("test", -1) == n - round(n * 0.7) - round(n * 0.15))
            check("provided split files cover all ids + disjoint",
                  part.get("cover") and part.get("disjoint"), repr(part.get("counts")))
            check("provided split proportions 70/15/15", props_ok, f"{props}")

    for hcsv in ("h_split.csv", "h_tiny.csv"):
        hp = os.path.join(HIDDEN, hcsv)
        if not os.path.isfile(hp):
            check(f"hidden {hcsv} determinism", False, "missing")
            continue
        hdf = _try(lambda: pd.read_csv(hp))
        r1 = run(["python3", SPLIT_PY, hp, "/tmp/hx1"])
        r2 = run(["python3", SPLIT_PY, hp, "/tmp/hx2"])
        det = all(os.path.isfile(f"/tmp/hx1_{k}.csv") and os.path.isfile(f"/tmp/hx2_{k}.csv")
                  and sig(f"/tmp/hx1_{k}.csv") == sig(f"/tmp/hx2_{k}.csv")
                  for k in ("train", "val", "test"))
        check(f"hidden {hcsv} split deterministic", det and r1.returncode == 0,
              r1.stderr.strip()[-120:])
        write_split(split_reference(hdf), "/tmp/hcan")
        canon = all(
            os.path.isfile(f"/tmp/hx1_{k}.csv") and
            pd.read_csv(f"/tmp/hx1_{k}.csv").equals(
                pd.read_csv(f"/tmp/hcan_{k}.csv"))
            for k in ("train", "val", "test"))
        part = _try(lambda: check_partition("/tmp/hx1", set(hdf["id"].astype(int))))
        check(f"hidden {hcsv} canonical + coverage",
              canon and isinstance(part, dict) and part.get("cover") and part.get("disjoint"),
              f"rc={r1.returncode} {part.get('counts') if isinstance(part, dict) else part}")

    # ================= 2. training reproduces a real model ====================
    if os.path.isfile(f"{APP}/train.py"):
        tr = run(["python3", TRAIN_PY, f"{APP}/split_train.csv",
                  f"{APP}/split_val.csv", "/tmp/train_recheck.pt"])
        acc = _try(lambda: snap_of("/tmp/train_recheck.pt", f"{APP}/split_train.csv"),
                   -1.0)
        check("train.py reproduces real snapshot acc>=0.90",
              tr.returncode == 0 and os.path.isfile("/tmp/train_recheck.pt") and
              acc >= TRAIN_ACC_TH, f"acc={acc:.3f} rc={tr.returncode}")
    if model is not None and os.path.isfile(f"{APP}/split_train.csv"):
        acc0 = _try(lambda: snap_of(BASE, f"{APP}/split_train.csv"), -1.0)
        check("model_snapshot train acc >= 0.90", acc0 >= TRAIN_ACC_TH,
              f"acc={acc0:.3f}")

    # ================= 3. prediction rows =====================================
    if model is not None and os.path.isfile(f"{APP}/predict.py"):
        ud = _try(lambda: pd.read_csv(f"{APP}/data/unlabeled.csv"))
        if isinstance(ud, pd.DataFrame) and len(ud):
            exp = _try(lambda: labels_text(model, ud[FEAT_COLS].to_numpy(
                dtype=np.float32)))
            pr = run(["python3", PREDICT_PY, f"{APP}/data/unlabeled.csv",
                      "/tmp/row_out.txt"])
            got = _try(lambda: open("/tmp/row_out.txt").read())
            check("pred_labels.txt == snapshot recompute",
                  got == exp and len(got.splitlines()) == 200,
                  f"rc={pr.returncode} lines={len(got.splitlines()) if got else -1}")
            art = _try(lambda: open(PRED_LABELS).read())
            check("/app/pred_labels.txt matches", art == exp)
            check("stdout == result file (exact digits)",
                  pr.stdout == got and all(x in ("0", "1") for x in got.split()))
        else:
            check("unlabeled.csv readable", False)

        hp = os.path.join(HIDDEN, "h_holdout.csv")
        if os.path.isfile(hp):
            hdf = _try(lambda: pd.read_csv(hp))
            hexp = _try(lambda: labels_text(model, hdf[FEAT_COLS].to_numpy(
                dtype=np.float32)))
            hrun = run(["python3", PREDICT_PY, hp, "/tmp/ho.txt"])
            hgot = _try(lambda: open("/tmp/ho.txt").read())
            check("hidden holdout file matches recompute",
                  hrun.returncode == 0 and hgot == hexp and len(hgot.splitlines()) > 0,
                  f"rc={hrun.returncode}")
            check("hidden holdout stdout == file", hrun.stdout == hgot)

        # empty-set edge (header only, zero rows) -> empty output
        pd.DataFrame(columns=["id"] + FEAT_COLS).to_csv("/tmp/e.csv", index=False)
        erun = run(["python3", f"{APP}/predict.py", "/tmp/e.csv", "/tmp/eout.txt"])
        eout = _try(lambda: open("/tmp/eout.txt").read())
        check("empty set -> empty output", erun.returncode == 0 and eout == "",
              f"rc={erun.returncode}")

        # malformed header -> non-zero exit
        open("/tmp/bad.csv", "w").write("id,x1\n0,1.0\n")
        brun = run(["python3", f"{APP}/predict.py", "/tmp/bad.csv", "/tmp/bout.txt"])
        check("missing-features input exits non-zero", brun.returncode != 0,
              f"rc={brun.returncode}")

        # non-numeric feature value -> non-zero exit (documented edge case)
        goodrow = ",".join(["0.5"] * (F - 1))
        open("/tmp/badnum.csv", "w").write(
            "id," + ",".join(FEAT_COLS) + "\n0," + goodrow + ",abc\n")
        nrun = run(["python3", f"{APP}/predict.py", "/tmp/badnum.csv", "/tmp/bn_out.txt"])
        check("non-numeric feature exits non-zero", nrun.returncode != 0,
              f"rc={nrun.returncode}")

    # ================= 4. finetune adapts to a fold ============================
    if os.path.isfile(f"{APP}/finetune.py") and os.path.isfile(BASE):
        hp = os.path.join(HIDDEN, "h_fold.csv")
        if os.path.isfile(hp):
            fr = run(["python3", FINETUNE_PY, hp, "/tmp/ft_snap.pt"])
            existed = os.path.isfile("/tmp/ft_snap.pt")
            facc = _try(lambda: snap_of("/tmp/ft_snap.pt", hp), -1.0)
            changed = existed and sig("/tmp/ft_snap.pt") != sig(BASE)
            check("finetune hidden fold -> new loadable snapshot",
                  fr.returncode == 0 and existed,
                  f"rc={fr.returncode} acc={facc:.3f}")
            check("finetune snapshot differs from base", changed)
            check("finetune fold accuracy >= 0.90", facc >= FINETUNE_ACC_TH,
                  f"acc={facc:.3f}")
        # provided fold (reusability) -- must at least complete
        dd = f"{APP}/data/finetune_fold.csv"
        if os.path.isfile(dd):
            q = run(["python3", FINETUNE_PY, dd, "/tmp/demo_ft.pt"])
            check("finetune.py reusable on provided fold", q.returncode == 0,
                  q.stderr.strip()[-100:])

    # ================= 5. bag scores ==========================================
    if model is not None and os.path.isfile(f"{APP}/predict.py"):
        bb = f"{APP}/data/big_bag.csv"
        ref = _try(lambda: bag_reference(model, bb))
        brun = run(["python3", PREDICT_PY, "--bag", bb, "/tmp/bb_out.txt"])
        bgot = _try(lambda: open("/tmp/bb_out.txt").read())
        bart = _try(lambda: open(BAG_SCORES).read())
        check("large_bag_scores.txt matches recompute",
              ref and bart == ref and brun.returncode == 0 and len(ref.splitlines()) == 6,
              f"rc={brun.returncode}")
        check("bag stdout == file", _try(lambda: brun.stdout) == bgot)

        hbag = os.path.join(HIDDEN, "h_bag.csv")
        if os.path.isfile(hbag):
            href = _try(lambda: bag_reference(model, hbag))
            hr = run(["python3", PREDICT_PY, "--bag", hbag, "/tmp/hbag_out.txt"])
            hgot = _try(lambda: open("/tmp/hbag_out.txt").read())
            check("hidden bag scores match recompute",
                  href and hgot == href and hr.returncode == 0,
                  f"rc={hr.returncode}")

        # bag edge: header-only bag file (zero patches) -> empty output, exit 0
        pd.DataFrame(columns=["bag_id"] + FEAT_COLS).to_csv("/tmp/ebag.csv", index=False)
        ebr = run(["python3", f"{APP}/predict.py", "--bag", "/tmp/ebag.csv",
                   "/tmp/ebag_out.txt"])
        ebg = _try(lambda: open("/tmp/ebag_out.txt").read())
        check("empty bag file -> empty output",
              ebr.returncode == 0 and ebg == "", f"rc={ebr.returncode}")

        # bag edge: non-numeric patch feature -> non-zero exit
        open("/tmp/badbag.csv", "w").write(
            "bag_id," + ",".join(FEAT_COLS) + "\n7," + goodrow + ",abc\n")
        bbr = run(["python3", f"{APP}/predict.py", "--bag", "/tmp/badbag.csv",
                   "/tmp/badbag_out.txt"])
        check("non-numeric bag feature exits non-zero", bbr.returncode != 0,
              f"rc={bbr.returncode}")

        # ---- big-memory stress bag: bounded RSS + deadline + correctness ----
        stress = "/tmp/stress_bag.csv"
        _sgen = _try(lambda: _write_stress_bag(stress, STRESS_ROWS), False)
        if _sgen:
            rc, rss, dt = _measure_bag(stress, "/tmp/stress_out.txt")
            sref = _try(lambda: bag_reference(model, stress))
            sgot = _try(lambda: open("/tmp/stress_out.txt").read())
            check("stress bag finished", rc == 0, f"rc={rc}")
            check("stress bag memory bounded", 0 < rss <= BAG_RSS_CAP_KB,
                  f"peak={rss} KiB cap={BAG_RSS_CAP_KB}")
            check("stress bag within deadline", dt <= BAG_TIME_MAX_S, f"{dt:.1f}s")
            check("stress bag scores match recompute", sgot == sref and len(sgot.split()) > 0)
        else:
            check("stress bag generated", False)

    failed = any(not ok for _, ok in CHECKS)
    print(f"TOTAL {len(CHECKS)} FAILED {sum(1 for _, ok in CHECKS if not ok)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        print("FAIL harness error")
        traceback.print_exc()
    failed = any(not ok for _, ok in CHECKS)
    print(f"TOTAL {len(CHECKS)} FAILED {sum(1 for _, ok in CHECKS if not ok)}")
    sys.exit(1 if failed else 0)