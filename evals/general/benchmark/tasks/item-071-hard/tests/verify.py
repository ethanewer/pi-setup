#!/usr/bin/env python3
"""Independent verifier for item-071-hard.

Rewards:
  1.0  everything passes (incl. a determinism re-run)
  0.5  run + artifacts + partition ok, but numbers do not match canonical
  0.0  run failed / artifacts missing / contract modified / nondeterministic
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


def run_engine():
    subprocess.run(["rm", "-rf", OUT], check=True)
    r = subprocess.run(["bash", os.path.join(ENER, "run.sh")],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=ENER)
    return r


def main():
    try:
        return run_all()
    except Exception as e:  # noqa: BLE001
        print("VERIFY ERROR:", repr(e))
        return "0.0"


def run_all():
    if not (os.path.exists(REF) and os.path.exists(GOLDEN)):
        return "0.0"
    if hashlib.sha256(open(REF, "rb").read()).digest() != \
       hashlib.sha256(open(GOLDEN, "rb").read()).digest():
        print("reference.py modified -> contract violation")
        return "0.0"

    reference = load_module("ref_golden", GOLDEN)
    tokens = torch.load(TOK)
    if tokens.shape != torch.Size([5, 4, 16]):
        print("tokens.pt bad shape", tuple(tokens.shape))
        return "0.0"

    if not (os.path.isfile(os.path.join(ENER, "run.sh")) and
            os.path.isfile(os.path.join(ENER, "main.py"))):
        return "0.0"

    r = run_engine()
    if r.returncode != 0:
        print("run.sh failed:\n", r.stdout.decode(errors="replace")[-4000:])
        return "0.0"
    for f in ("w_stage0.pt", "w_stage1.pt", "report.json"):
        if not os.path.isfile(os.path.join(OUT, f)):
            print("missing", f)
            return "0.0"

    with open(os.path.join(OUT, "report.json")) as fh:
        report = json.load(fh)

    # ---- schema ----
    if report.get("flavor") != "hard":
        print("flavor != hard")
        return "0.0"
    if report.get("world") != {"pipeline_stages": 2, "tensor_parallel_size": 1,
                               "total_ranks": 2,
                               "stage_ranks": {"stage0": [0], "stage1": [1]}}:
        print("world schema")
        return "0.0"
    if report.get("model") != {"vocab": 64, "d_model": 32, "n_heads": 8,
                               "head_dim": 4, "layers": 6}:
        print("model schema")
        return "0.0"
    if report.get("layers_per_stage") != [3, 3]:
        print("layers_per_stage schema")
        return "0.0"
    tr = report.get("training") or {}
    if tr.get("steps") != 4 or tr.get("microbatches") != 2 or tr.get("lr") != 0.05:
        print("training schema")
        return "0.0"
    if not isinstance(report.get("per_step_microbatch_losses"), list) or \
       len(report["per_step_microbatch_losses"]) != 4:
        print("losses schema")
        return "0.0"
    if not isinstance(report.get("gradient_equivalence"), dict):
        print("gradient schema")
        return "0.0"

    # ---- canonical 4-step SGD loop from the reference ----
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

    ok_losses = True
    for s in range(4):
        for m in (0, 1):
            got = report["per_step_microbatch_losses"][s][m]
            want = per[s][m]
            if abs(got - want) > 1e-2:
                ok_losses = False
                print(f"loss mismatch step {s} micro {m}: got {got} want {want}")
    if abs(report["final_loss"] - final_loss) > 1e-3:
        ok_losses = False
        print(f"final_loss mismatch: got {report['final_loss']} want {final_loss}")

    # ---- partition + weights ----
    all_names = set(reference.full_name_set())
    w0 = torch.load(os.path.join(OUT, "w_stage0.pt"))
    w1 = torch.load(os.path.join(OUT, "w_stage1.pt"))
    exp0 = {k for k in all_names if k == "embed" or
           (k.startswith("blocks.") and int(k.split(".")[1]) in (0, 1, 2))}
    exp1 = all_names - exp0
    ok_partition = set(w0.keys()) == exp0 and set(w1.keys()) == exp1
    if not ok_partition:
        print("partition mismatch")
        print("  stage0 delta:", sorted(set(w0.keys()) ^ exp0))
        print("  stage1 delta:", sorted(set(w1.keys()) ^ exp1))

    ok_weights = ok_partition
    if ok_weights:
        for k in w0:
            if (w0[k] - p[k]).abs().max().item() > 5e-4:
                ok_weights = False
                print("stage0 weight mismatch", k)
        for k in w1:
            if (w1[k] - p[k]).abs().max().item() > 5e-4:
                ok_weights = False
                print("stage1 weight mismatch", k)

    # ---- gradient_equivalence sanity ----
    ge = report["gradient_equivalence"]
    ok_grad = False
    n = int(ge.get("num_tensors_compared", 0))
    mrd = float(ge.get("max_rel_diff", 99.0))
    mad = float(ge.get("max_abs_diff", 99.0))
    if 30 <= n <= 45 and n == len(all_names) and mrd < 0.01 and mad < 0.05 \
       and mad >= 0.0 and mrd >= 0.0:
        ok_grad = True
    else:
        print("gradient_equivalence sanity failed:", ge)

    # ---- determinism: re-run, compare numeric report fields ----
    ok_det = False
    if ok_losses and ok_weights and ok_grad:
        r2 = run_engine()
        if r2.returncode == 0 and os.path.isfile(os.path.join(OUT, "report.json")):
            with open(os.path.join(OUT, "report.json")) as fh:
                report2 = json.load(fh)
            ok_det = (report["per_step_microbatch_losses"] == report2["per_step_microbatch_losses"]
                      and report["final_loss"] == report2["final_loss"]
                      and report["gradient_equivalence"] == report2["gradient_equivalence"])
            if not ok_det:
                print("nondeterministic re-run")

    if ok_losses and ok_weights and ok_grad and ok_det:
        return "1.0"
    if ok_losses and ok_weights and ok_grad:
        return "0.5"
    return "0.0"


if __name__ == "__main__":
    sys.stdout.write(main() + "\n")