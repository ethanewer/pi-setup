#!/bin/bash
# Verifier for rust-bazaar: checks the deliverables exist, ENFORCES the
# no-modify rule on the supplied /app fixtures, and EXECUTES the deliverable
# program (/app/finetune.py) on the visible fold and on every hidden fold in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine fixtures (copied at image build time to /opt/pristine); tampering
# with /app/base_snapshot.pt or /app/data/line_fold.csv breaks the checks.
no_modify_broken=0
for pair in "/app/base_snapshot.pt:/opt/pristine/base_snapshot.pt" \
            "/app/data/line_fold.csv:/opt/pristine/line_fold.csv"; do
    live="${pair%%:*}"; pristine="${pair##*:}"
    if [ ! -f "$live" ] || [ ! -f "$pristine" ]; then
        echo "no-modify: missing $live or $pristine" >&2
        no_modify_broken=1
    elif [ "$(sha256sum "$live" | awk '{print $1}')" != \
           "$(sha256sum "$pristine" | awk '{print $1}')" ]; then
        echo "no-modify: $live was modified" >&2
        no_modify_broken=1
    fi
done

python3 - "$no_modify_broken" <<'PY'
import hashlib, os, re, subprocess, sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

APP = "/app"
HIDDEN = "/tests/hidden"
FINETUNER = "/app/finetune.py"
BASE = "/app/base_snapshot.pt"
VISIBLE_FOLD = "/app/data/line_fold.csv"
VISIBLE_OUT = "/app/ft_visible.pt"
F, H, C = 24, 48, 3
FEATS = [f"x{i}" for i in range(F)]
ACC_TH = 0.90
CHECKS = []


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(F, H)
        self.l2 = nn.Linear(H, C)

    def forward(self, x):
        return self.l2(torch.relu(self.l1(x)))


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
    Linear(24->48), ReLU, Linear(48->3) -- regardless of parameter naming."""
    if not isinstance(sd, dict) or len(sd) != 4:
        return False
    if sum(1 for k in sd if k.endswith(".weight")) != 2:
        return False
    if sum(1 for k in sd if k.endswith(".bias")) != 2:
        return False
    shapes = {tuple(v.shape) for v in sd.values()}
    return shapes == {(C,), (H,), (H, F), (C, H)}


def load_model(path):
    sd = torch.load(path, map_location="cpu")
    if not arch_ok(sd):
        raise ValueError("state_dict is not a 24->48->3 two-Linear net")
    fresh = {}
    for k, v in sd.items():
        root = "l1" if tuple(v.shape) in ((H, F), (H,)) else "l2"
        suffix = ".weight" if k.endswith(".weight") else ".bias"
        fresh[root + suffix] = v.float()
    m = Net()
    m.load_state_dict(fresh)
    m.eval()
    return m


def snap_acc(path, fold_csv):
    df = pd.read_csv(fold_csv)
    X = torch.from_numpy(df[FEATS].to_numpy(dtype=np.float32))
    y = torch.from_numpy(df["label"].to_numpy(dtype=np.int64))
    m = load_model(path)
    with torch.no_grad():
        pred = m(X).argmax(1)
    return float((pred == y).float().mean())


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def run_ft(fold, out):
    return subprocess.run(["python3", FINETUNER, fold, out],
                          capture_output=True, text=True, timeout=120)


def check_ft_run(tag, fold):
    out = f"/tmp/ft_{tag}.pt"
    if os.path.exists(out):
        os.remove(out)
    r = run_ft(fold, out)
    if r.returncode != 0 or not os.path.isfile(out):
        check(f"{tag}: finetune.py exits 0 and writes snapshot", False,
              f"rc={r.returncode} err={r.stderr.strip()[-160:]}")
        return
    check(f"{tag}: finetune.py exits 0 and writes snapshot", True)
    check(f"{tag}: prints finetune_accuracy= line",
          any(re.match(r"^finetune_accuracy=", ln)
              for ln in r.stdout.splitlines()), r.stdout.strip()[:80])
    ok_arch = _try(lambda: arch_ok(torch.load(out, map_location="cpu")), False)
    check(f"{tag}: snapshot is a valid 24->48->3 state_dict", bool(ok_arch))
    changed = _try(lambda: sha(out) != sha(BASE), False)
    check(f"{tag}: snapshot differs from base", bool(changed))
    acc = _try(lambda: snap_acc(out, fold), -1.0)
    check(f"{tag}: fold accuracy >= {ACC_TH}", isinstance(acc, float) and acc >= ACC_TH,
          f"acc={acc}")


def main():
    no_modify_broken = int(sys.argv[1])
    check("no-modify: fixtures untouched", no_modify_broken == 0)

    for f in ["finetune.py", "ft_visible.pt"]:
        check(f"exists {APP}/{f}", os.path.isfile(f"{APP}/{f}"))
    check("visible fixtures present",
          os.path.isfile(BASE) and os.path.isfile(VISIBLE_FOLD))

    base_ok = _try(lambda: arch_ok(torch.load(BASE, map_location="cpu")), False)
    check("base snapshot is a valid 24->48->3 state_dict", bool(base_ok))

    # ---- visible artifact --------------------------------------------------
    if os.path.isfile(VISIBLE_OUT) and os.path.isfile(VISIBLE_FOLD):
        ok_arch = _try(lambda: arch_ok(torch.load(VISIBLE_OUT, map_location="cpu")), False)
        check("ft_visible.pt is a valid 24->48->3 state_dict", bool(ok_arch))
        changed = _try(lambda: sha(VISIBLE_OUT) != sha(BASE), False)
        check("ft_visible.pt differs from base", bool(changed))
        acc = _try(lambda: snap_acc(VISIBLE_OUT, VISIBLE_FOLD), -1.0)
        check(f"ft_visible.pt fold accuracy >= {ACC_TH}",
              isinstance(acc, float) and acc >= ACC_TH, f"acc={acc}")

    # ---- reusability: re-run the deliverable on the visible fold -----------
    if os.path.isfile(FINETUNER) and os.path.isfile(VISIBLE_FOLD):
        check_ft_run("visible_recheck", VISIBLE_FOLD)

    # ---- hidden folds: independent labeling rules --------------------------
    if os.path.isdir(HIDDEN):
        cases = sorted(os.listdir(HIDDEN))
        if not cases:
            check("hidden folds present", False, "no hidden cases")
        for c in cases:
            fold = os.path.join(HIDDEN, c)
            if not os.path.isfile(fold):
                check(f"hidden {c} is a file", False)
                continue
            if os.path.isfile(FINETUNER):
                check_ft_run(f"hidden_{c}", fold)

    # ---- error-handling edges ----------------------------------------------
    if os.path.isfile(FINETUNER):
        # missing feature column (23 features)
        cols = ["id"] + FEATS[:-1] + ["label"]
        pd.DataFrame(np.zeros((5, len(cols))), columns=cols).to_csv(
            "/tmp/bad_cols.csv", index=False)
        r = run_ft("/tmp/bad_cols.csv", "/tmp/bad_cols.pt")
        check("missing feature column exits non-zero", r.returncode != 0,
              f"rc={r.returncode}")

        # zero data rows (header only)
        pd.DataFrame(columns=["id"] + FEATS + ["label"]).to_csv(
            "/tmp/empty.csv", index=False)
        r = run_ft("/tmp/empty.csv", "/tmp/empty.pt")
        check("zero-row fold exits non-zero", r.returncode != 0, f"rc={r.returncode}")

        # non-numeric feature value
        row = ["1"] + ["0.5"] * (F - 1) + ["abc", "0"]
        with open("/tmp/badnum.csv", "w") as fh:
            fh.write("id," + ",".join(FEATS) + ",label\n")
            fh.write(",".join(row) + "\n")
        r = run_ft("/tmp/badnum.csv", "/tmp/badnum.pt")
        check("non-numeric feature exits non-zero", r.returncode != 0,
              f"rc={r.returncode}")

    failed = sum(1 for _, ok in CHECKS if not ok)
    print(f"TOTAL {len(CHECKS)} FAILED {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        print("FAIL harness error")
        traceback.print_exc()
        sys.exit(1)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
