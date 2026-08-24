#!/usr/bin/env python3
"""Independent verifier for item-071-main.

Rewards:
  1.0  everything passes
  0.5  run + artifacts + partition ok, but numeric values do not match canonical
  0.0  run failed / artifacts missing / contract modified
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

import torch

ENER = "/app/engine"
OUT = "/app/engine/out"
GOLDEN = "/tests/reference_golden.py"
REF = "/app/reference.py"
TOK = "/app/data/tokens.pt"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    try:
        return run()
    except Exception as e:  # noqa: BLE001
        print("VERIFY ERROR:", repr(e))
        return "0.0"


def run():
    # 1. the contract file must be untouched
    if not (os.path.exists(REF) and os.path.exists(GOLDEN)):
        return "0.0"
    if hashlib.sha256(open(REF, "rb").read()).digest() != \
       hashlib.sha256(open(GOLDEN, "rb").read()).digest():
        print("reference.py was modified -> contract violation")
        return "0.0"

    reference = load_module("ref_golden", GOLDEN)
    tokens = torch.load(TOK)  # (5,4,16)
    if tokens.shape != torch.Size([5, 4, 16]):
        return "0.0"

    # 2. re-run the harness from a clean slate
    if not (os.path.isfile(os.path.join(ENER, "run.sh")) and
            os.path.isfile(os.path.join(ENER, "main.py"))):
        return "0.0"
    subprocess.run(["rm", "-rf", OUT], check=True)
    r = subprocess.run(["bash", os.path.join(ENER, "run.sh")],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=ENER)
    if r.returncode != 0:
        print("run.sh failed:\n", r.stdout.decode(errors="replace")[-4000:])
        return "0.0"
    for f in ("w_stage0.pt", "w_stage1.pt", "report.json"):
        if not os.path.isfile(os.path.join(OUT, f)):
            print("missing", f)
            return "0.0"

    with open(os.path.join(OUT, "report.json")) as fh:
        report = json.load(fh)

    # 3. schema fields
    if report.get("flavor") != "main":
        return "0.0"
    if report.get("world") != {"pipeline_stages": 2, "tensor_parallel_size": 1,
                               "total_ranks": 2, "stage_ranks": {"stage0": [0], "stage1": [1]}}:
        return "0.0"
    if report.get("model") != {"vocab": 64, "d_model": 32, "n_heads": 8,
                               "head_dim": 4, "layers": 6}:
        return "0.0"
    if report.get("layers_per_stage") != [3, 3]:
        return "0.0"
    tr = report.get("training") or {}
    if tr.get("steps") != 4 or tr.get("microbatches") != 2 or tr.get("lr") != 0.05:
        return "0.0"
    if not isinstance(report.get("per_step_microbatch_losses"), list) or \
       len(report["per_step_microbatch_losses"]) != 4:
        return "0.0"
    if not isinstance(report.get("gradient_equivalence"), dict):
        return "0.0"

    # 4. canonical single-process 4-step SGD loop
    p = reference.build_params(seed=20260407)
    per = []
    for s in range(4):
        row = []
        for m in (0, 1):
            mb = tokens[s, m * 2:(m + 1) * 2]
            row.append(reference.loss(p, mb).item())
        per.append(row)
        g, _ = reference.grads(p, tokens[s])
        p = reference.sgd_update(p, g, 0.05)
    final_loss = reference.loss(p, tokens[3]).item()

    basic_ok = True

    # per-micro losses
    ok_losses = True
    for s in range(4):
        for m in (0, 1):
            got = report["per_step_microbatch_losses"][s][m]
            if abs(got - per[s][m]) > 1e-2:
                ok_losses = False
                print(f"loss mismatch step {s} micro {m}: got {got} want {per[s][m]}")
    if abs(report["final_loss"] - final_loss) > 1e-3:
        ok_losses = False
        print(f"final_loss mismatch: got {report['final_loss']} want {final_loss}")

    # 5. partition / weights
    full_names = set(reference.full_name_set())
    w0 = torch.load(os.path.join(OUT, "w_stage0.pt"))
    w1 = torch.load(os.path.join(OUT, "w_stage1.pt"))
    exp0 = {k for k in full_names if k == "embed" or
            (k.startswith("blocks.") and int(k.split(".")[1]) in (0, 1, 2))}
    exp1 = full_names - exp0
    if set(w0.keys()) != exp0 or set(w1.keys()) != exp1:
        basic_ok = False
        print("partition mismatch")
    ok_weights = True
    if basic_ok:
        for k in w0:
            if (w0[k] - p[k]).abs().max().item() > 5e-4:
                ok_weights = False
                print("stage0 weight mismatch", k)
        for k in w1:
            if (w1[k] - p[k]).abs().max().item() > 5e-4:
                ok_weights = False
                print("stage1 weight mismatch", k)
    else:
        ok_weights = False

    # 6. gradient_equivalence sanity
    ge = report["gradient_equivalence"]
    ok_grad = False
    if isinstance(ge.get("num_tensors_compared"), (int, float)):
        n = int(ge["num_tensors_compared"])
        mr = float(ge.get("max_rel_diff", 99.0))
        ma = float(ge.get("max_abs_diff", 99.0))
        if 30 <= n <= 45 and n == len(full_names) and mr < 0.01 and ma < 0.05 and \
           ma >= 0.0 and mr >= 0.0:
            ok_grad = True

    if ok_losses and ok_weights and ok_grad and basic_ok:
        return "1.0"
    if basic_ok and ok_weights and ok_grad:
        return "0.5"
    return "0.0"


if __name__ == "__main__":
    sys.stdout.write(main() + "\n")