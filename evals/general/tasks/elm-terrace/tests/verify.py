#!/usr/bin/env python3
"""Verifier for elm-terrace. All checks; exits 0 with reward written by test.sh.
Runs inside the agent container after it finishes. Never modifies /tests.

Only the DOCUMENTED contract (instruction.md) is enforced: the `load` CLI on
/app/reconstruct.py, the deliverables under /app, the documented model family
(Linear+ReLU blocks + head Linear), and the documented state-dict container
forms (bare tensor mapping, or wrapped under a single key like {"d": {...}}).
No module-level function names of the agent's reconstruct.py are assumed.
"""
import json
import os
import subprocess
import sys

import numpy as np
import torch
import torch.nn as nn

APP = "/app"
REC = "/app/reconstruct.py"
TRITON = "/app/triton_cpu.py"
STATE = "/opt/causal/data/state_dict.pt"
HOLDOUT = "/opt/causal/data/holdout.csv"
MAX_MODEL_BYTES = 100_000
RANK = 2

failures = []


def check(label, cond, why=""):
    if cond:
        print(f"PASS  {label}")
    else:
        print(f"FAIL  {label}  {why}")
        failures.append(label)


def file_size_dir(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    return total


def normalize_state(obj):
    """Documented container forms: either a bare {name: tensor} mapping, or a
    single wrapping key like {'d': {name: tensor, ...}} -> return the bare one."""
    if isinstance(obj, dict) and obj and all(isinstance(v, torch.Tensor) for v in obj.values()):
        return dict(obj)
    if (
        isinstance(obj, dict)
        and len(obj) == 1
    ):
        inner = next(iter(obj.values()))
        if isinstance(inner, dict) and inner and all(isinstance(t, torch.Tensor) for t in inner.values()):
            return dict(inner)
    raise ValueError("not a recognized state-dict container")


def reconstruct_cli(dict_path):
    """Run the documented `load` subcommand and verify its documented outputs:
    arch JSON on stdout, exit 0, saved {"arch": ..., "state_dict": ...} whose
    state_dict reproduces the source tensors exactly."""
    outp = "/tmp/vout.pt"
    r = subprocess.run(
        [sys.executable, REC, "load", dict_path, outp],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return False, f"exit={r.returncode}: {r.stderr[-200:]}"
    try:
        arch = json.loads(r.stdout.strip().splitlines()[-1])
        saved = torch.load(outp, map_location="cpu", weights_only=True)
        saved_arch = saved["arch"]
        saved_sd = saved["state_dict"]
    except Exception as e:
        return False, f"bad out.pt/arch json: {e}"
    if saved_arch != arch:
        return False, "arch mismatch stdout vs saved"
    try:
        src = normalize_state(torch.load(dict_path, map_location="cpu", weights_only=True))
        saved_sd = normalize_state(saved_sd)
    except Exception as e:
        return False, f"state normalization failed: {e}"
    if set(src) != set(saved_sd):
        return False, "key set mismatch"
    for k in src:
        if not torch.allclose(src[k].float(), saved_sd[k].float()):
            return False, f"value mismatch {k}"
    return True, arch


# Documented architecture family: fcs.<i> = Linear + ReLU, head = output Linear.
class TinyCausal(nn.Module):
    def __init__(self, arch):
        super().__init__()
        in_dim = int(arch["input"])
        hidden = int(arch["hidden"])
        out_dim = int(arch["head"])
        blocks = int(arch["blocks"])
        self.fcs = nn.ModuleList(
            [
                nn.Linear(in_dim if i == 0 else hidden, hidden)
                for i in range(blocks)
            ]
        )
        self.head = nn.Linear(hidden, out_dim)

    def forward(self, x):
        for fc in self.fcs:
            x = torch.relu(fc(x))
        return self.head(x)


def main():
    # ---- 1. visibility of deliverables ----
    for path in [
        "/app/reconstruct.py",
        "/app/triton_cpu.py",
        "/app/lt_triton_result.json",
        "/app/preds.csv",
        "/app/sample.csv",
        "/app/lowrank.npz",
        "/app/model/adapter_config.json",
        "/app/model/state_dict.pt",
        "/app/model/arch.json",
    ]:
        check("deliverable " + path, os.path.isfile(path))

    # ---- 2. reconstruct on committed dict ----
    okc, arc = reconstruct_cli(STATE)
    check("reconstruct committed", okc, arc if not okc else "")

    # ---- 3. reconstruct on every hidden dict (generalization) ----
    hidden_dir = "/tests/hidden"
    hidden_ok = True
    hidden_cnt = 0
    if os.path.isdir(hidden_dir):
        for c in sorted(os.listdir(hidden_dir)):
            d = os.path.join(hidden_dir, c)
            sd = os.path.join(d, "state_dict.pt")
            if not os.path.isfile(sd):
                hidden_ok = False
                continue
            ok_, a = reconstruct_cli(sd)
            hidden_cnt += 1
            expected = {}
            ej = os.path.join(d, "expected.json")
            if os.path.isfile(ej):
                expected = json.load(open(ej))
            if expected and a:
                ok_ = ok_ and all(a.get(k) == expected[k] for k in ("input", "hidden", "head", "blocks"))
            check(f"reconstruct hidden/{c}", ok_, a if not ok_ else "")
            hidden_ok = hidden_ok and ok_
    check("hidden count >= 2", hidden_cnt >= 2, f"got {hidden_cnt}")
    check("reconstruct all hidden", hidden_ok)

    # ---- 3-bis. published arch.json / base weights match the committed reconstruction ----
    pub_ok = True
    try:
        arch_json = json.load(open("/app/model/arch.json"))
        if not (okc and arc):
            pub_ok = False
        elif arch_json != arc:
            pub_ok = False
            print("  arch.json mismatch vs committed reconstruction:", arch_json)
        else:
            base_sd = torch.load("/app/model/state_dict.pt", map_location="cpu", weights_only=True)
            src = normalize_state(torch.load(STATE, map_location="cpu", weights_only=True))
            if set(src) != set(base_sd):
                pub_ok = False
                print("  model/state_dict.pt key set mismatch vs committed dict")
            else:
                for k in src:
                    if torch.allclose(src[k].float(), base_sd[k].float()) is False:
                        pub_ok = False
                        print(f"  model/state_dict.pt value mismatch {k}")
    except Exception as e:
        print("arch.json/state_dict.pt eval error:", e)
        pub_ok = False
    check("published arch.json matches reconstruct", pub_ok)

    # ---- 4. model size budget ----
    size = file_size_dir(APP + "/model")
    check("model size <= 100KB", size <= MAX_MODEL_BYTES, f"{size} bytes")

    # ---- 5. LoRA adapter config ----
    ac = {}
    try:
        ac = json.load(open("/app/model/adapter_config.json"))
    except Exception as e:
        print("  adapter_config unreadable:", e)
    check(
        "adapter config fields",
        (ac.get("r") == RANK)
        and (ac.get("lora_alpha") == 8)
        and (ac.get("bias") == "none")
        and (ac.get("task_type") == "CAUSAL_LM")
        and (set(ac.get("target_modules", [])) == {"fc0", "fc1"})
        and (ac.get("base_model_name_or_path") == "elm-terrace-tiny-causal")
        and (ac.get("inference_mode") is True),
        str(ac),
    )

    # ---- 6. lowrank factors ----
    lr_ok = False
    try:
        lr = np.load("/app/lowrank.npz")
        keys = {"U_fc0", "V_fc0", "U_fc1", "V_fc1", "U_head", "V_head"}
        if set(lr.files) == keys:
            lr_ok = True
            for k in ("U_fc0", "U_fc1"):
                if lr[k].shape[1] != RANK:
                    lr_ok = False
            for k in ("V_fc0", "V_fc1"):
                if lr[k].shape[0] != RANK:
                    lr_ok = False
            for pair in (("U_fc0", "V_fc0"), ("U_fc1", "V_fc1"), ("U_head", "V_head")):
                if np.linalg.matrix_rank((lr[pair[0]] @ lr[pair[1]])) > RANK:
                    lr_ok = False
    except Exception as e:
        print("lowrank err", e)
    check("lowrank schema/rank", lr_ok)

    # ---- 7. preds.csv rows + intervened model beats untuned base ----
    # Base model is built from the documented deliverables arch.json + state_dict.pt.
    try:
        predb = np.loadtxt("/app/preds.csv", delimiter=",", skiprows=1).reshape(-1)
        hold = np.loadtxt(HOLDOUT, delimiter=",", skiprows=1)
        y_true = hold[:, 7]
        arch = json.load(open("/app/model/arch.json"))
        base_model = TinyCausal(arch)
        base_sd = torch.load("/app/model/state_dict.pt", map_location="cpu", weights_only=True)
        base_model.load_state_dict(base_sd, strict=True)
        base_model.eval()
        x_hold = torch.from_numpy(hold[:, :7].astype(np.float32)) if hold.ndim == 2 else None
        with torch.no_grad():
            base_pred = base_model(x_hold).reshape(-1).numpy()
        base_mse = float(np.mean((base_pred - y_true) ** 2))
        agent_mse = float(np.mean((predb - y_true) ** 2))
        finite = bool(np.isfinite(predb).all())
        check("preds 100 rows", predb.shape[0] == 100, str(predb.shape[0]))
        check("preds finite", finite)
        check("intervened beats base (mse)",
              agent_mse < 0.6 * base_mse,
              f"agent {agent_mse:.4f} vs base {base_mse:.4f}")
    except Exception as e:
        print("preds eval error:", e)
        check("preds eval", False, str(e))

    # ---- 8. sample.csv ----
    try:
        sam = np.loadtxt("/app/sample.csv", delimiter=",", skiprows=1)
        if sam.ndim == 1:
            sam = sam.reshape(1, -1)
        feats_ok = bool((sam[:, :7] >= -1e-6).all() and (sam[:, :7] <= 1.0 + 1e-6).all())
        sample_ok = (
            sam.shape[0] == 1000
            and sam.shape[1] == 8
            and feats_ok
            and bool(np.isfinite(sam).all())
        )
        check("sample.csv 1000x8 4 [0,1] feats", sample_ok, str(sam.shape))
    except Exception as e:
        print("sample FAIL", e)
        check("sample.csv", False, str(e))

    # ---- 9. Triton CPU interpreter ----
    env = dict(os.environ)
    env["TRITON_INTERPRET"] = "1"
    try:
        rtr = subprocess.run(
            [sys.executable, TRITON], capture_output=True, text=True, env=env
        )
        triton_ok = rtr.returncode == 0
        tres = {}
        try:
            tres = json.load(open("/app/lt_triton_result.json"))
        except Exception as e:
            print("triton json read", e)
        check("triton runs exit0", triton_ok, rtr.stderr[-200:])
        check("triton result match true", bool(tres.get("match") is True))
    except Exception as e:
        print("triton run fail", e)
        check("triton runs exit0", False, str(e))

    print("FAIL_COUNT", len(failures))
    return failures


if __name__ == "__main__":
    fails = main()
    sys.exit(0 if not fails else 1)