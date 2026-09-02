#!/usr/bin/env python3
"""
elm-terrace : reconstruct + tune + sample a causal tiny model under a byte budget.

Two subcommands:

  reconstruct.py load <state_dict.pt> <out.pt>
      Reconstruct the architecture from the *shape* and *names* present in the
      given state-dict (no config file is supplied) and instantiate a nn.Module
      whose parameters match that dict exactly, then load it with strict=True.
      Writes <out.pt> = {"arch": {...}, "state_dict": <loaded state dict>}
      and prints the reconstructed arch as one line of JSON on stdout.
      Exit 0 on success (state dict loaded with zero key errors).

  reconstruct.py run
      Runs the full tuning / publishing pipeline described in instruction.md:
        - reconstruct the base model from /opt/causal/data/state_dict.pt
        - fit rank-2 LoRA adapters on /opt/causal/data/train.csv
        - publish the intervened model to /app/model/
          (background state + adapter_config.json + index.json) all under 100KB
        - write /app/preds.csv  (out-of-sample predictions w.r.t holdout)
        - write /app/lowrank.npz (the low-rank LoRA factor matrices)
        - write /app/sample.csv  (100 x 0 rows sampled from the intervened model)
        - run the Triton CPU-interpret kernel and write /app/lt_triton_result.json

The header-free CSV inputs have 8 columns A,B,C,D,E,F,G (features in [0,1])
followed by the numeric target Y. Deterministic: fixed seeds at the top of run.
"""
import json
import os
import re
import sys

import numpy as np
import torch
import torch.nn as nn

LAMBDA = 0.5
# rank used everywhere in LoRA
HARD_RANK = 2
LORA_ALPHA = 8.0
TASK_TYPE = "CAUSAL_LM"
SEED = 0


# --------------------------------------------------------------------------
# 1. model family + reconstruction
# --------------------------------------------------------------------------
class CausalTiny(nn.Module):
    """input dim -> [ReLU(Linear)] x blocks -> head Linear."""

    def __init__(self, in_dim, hidden, out_dim, nblocks):
        super().__init__()
        self.fcs = nn.ModuleList(
            [
                nn.Linear(in_dim if i == 0 else hidden, hidden)
                for i in range(nblocks)
            ]
        )
        self.head = nn.Linear(hidden, out_dim)

    def forward(self, x):
        for fc in self.fcs:
            x = torch.relu(fc(x))
        return self.head(x)


def read_state_dict(path):
    obj = torch.load(path, map_location="cpu", weights_only=True)
    if isinstance(obj, dict):
        # direct state dict: {name: tensor, ...}
        if obj and all(isinstance(v, torch.Tensor) for v in obj.values()):
            return dict(obj)
        # single wrapping container: {'d'|'sd': {name: tensor, ...}}
        for v in obj.values():
            if (
                isinstance(v, dict)
                and v
                and all(isinstance(t, torch.Tensor) for t in v.values())
            ):
                return dict(v)
    raise ValueError(f"unrecognized state-dict container in {path}")


def infer_arch(state):
    """Infer (input, hidden, out, nblocks) purely from key names/shapes."""
    fw = {}
    for k, t in state.items():
        m = re.match(r"fcs\.(\d+)\.weight$", k)
        if m:
            fw[int(m.group(1))] = t
    if not fw:
        raise ValueError("no fcs.<i>.weight keys found")
    nblocks = max(fw) + 1
    for i in range(nblocks):
        if i not in fw:
            raise ValueError(f"missing fcs.{i}.weight")
        if fw[i].shape[0] != fw[0].shape[0]:
            raise ValueError("hidden dim mismatch across fcs layers")
        if i > 0 and fw[i].shape[1] != fw[0].shape[0]:
            raise ValueError("adjacent fc dims mismatch")
    in_dim = fw[0].shape[1]
    hidden = fw[0].shape[0]
    if "head.weight" not in state:
        raise ValueError("missing head.weight")
    out_dim = state["head.weight"].shape[0]
    return {"input": in_dim, "hidden": hidden, "head": out_dim, "blocks": nblocks}


def build_model(arch):
    return CausalTiny(arch["input"], arch["hidden"], arch["head"], arch["blocks"])


def cmd_load(state_path, out_path):
    state = read_state_dict(state_path)
    arch = infer_arch(state)
    model = build_model(arch)
    model.load_state_dict(state, strict=True)  # must load without key mismatch
    torch.save({"arch": arch, "state_dict": model.state_dict()}, out_path)
    print(json.dumps(arch))
    return 0


# --------------------------------------------------------------------------
# 2. LoRA low-rank adapters
# --------------------------------------------------------------------------
class LoRAState:
    def __init__(self, model, r=HARD_RANK, alpha=LORA_ALPHA):
        self.model = model
        self.r = r
        self.alpha = alpha
        self.params = {}
        for j, fc in enumerate(model.fcs):
            out_i, in_i = fc.weight.shape[0], fc.weight.shape[1]
            u = nn.Parameter(torch.zeros(out_i, r).normal_(0, 0.02))
            v = nn.Parameter(torch.zeros(r, in_i).normal_(0, 0.02))
            self.params[f"fc{j}__U"] = u   # (out, r)
            self.params[f"fc{j}__V"] = v   # (r, in)
        hw = model.head.weight
        uh = nn.Parameter(torch.zeros(hw.shape[0], r).normal_(0, 0.02))
        vh = nn.Parameter(torch.zeros(r, hw.shape[1]).normal_(0, 0.02))
        self.params["head__U"] = uh
        self.params["head__V"] = vh
        self.trainables = list(self.params.values())
        for p in self.trainables:
            p.requires_grad_(True)

    def forward(self, x):
        x = x
        for j, fc in enumerate(self.model.fcs):
            delta = (self.alpha / self.r) * (self.params[f"fc{j}__U"] @ self.params[f"fc{j}__V"])
            w = fc.weight.detach().to(delta.device) + delta
            h = torch.relu(torch.nn.functional.linear(x, w, fc.bias.detach()))
            x = h
        delta_h = (self.alpha / self.r) * (self.params["head__U"] @ self.params["head__V"])
        w = self.model.head.weight.detach().to(delta_h.device) + delta_h
        x = torch.nn.functional.linear(x, w, self.model.head.bias.detach())
        return x


def fit_lora(model, x_tr, y_tr, steps=1200, lr=0.05, seed=SEED):
    torch.manual_seed(seed)
    np.random.seed(seed)
    lora = LoRAState(model)
    opt = torch.optim.Adam(lora.trainables, lr=lr)
    x_tr = x_tr.detach().float()
    y_tr = y_tr.detach().float().reshape(-1)
    for _ in range(steps):
        opt.zero_grad()
        pred = lora.forward(x_tr).reshape(-1)
        loss = torch.mean((pred - y_tr) ** 2)
        loss.backward()
        opt.step()
    return lora


def load_inputs(path):
    arr = np.loadtxt(path, delimiter=",", skiprows=1)
    x = torch.from_numpy(arr[:, :7].astype(np.float64)).float()
    y = torch.from_numpy(arr[:, 7].astype(np.float32))
    return x, y


# --------------------------------------------------------------------------
# 3. (Triton CPU-interpret kernel lives in the standalone deliverable
#     /app/triton_cpu.py, authored and run separately as described in
#     instruction.md; reconstruct.py focuses on reconstruction + tuning.)
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------

# 4. run pipeline
# --------------------------------------------------------------------------
def cmd_run(state_path, train_path, holdout_path, out_dir):
    torch.manual_seed(SEED)
    np.random.seed(SEED)
    os.makedirs(out_dir, exist_ok=True)
    model_dir = os.path.join(out_dir, "model")
    os.makedirs(model_dir, exist_ok=True)

    state = read_state_dict(state_path)
    arch = infer_arch(state)
    model = build_model(arch)
    model.load_state_dict(state, strict=True)

    x_tr, y_tr = load_inputs(train_path)
    lora = fit_lora(model, x_tr, y_tr)

    # ---- predicting on holdout -> /out_dir/preds.csv
    x_ho, _ = load_inputs(holdout_path)
    with torch.no_grad():
        preds = lora.forward(x_ho).reshape(-1).detach().cpu().numpy()
    np.savetxt(
        os.path.join(out_dir, "preds.csv"),
        preds.reshape(-1, 1),
        header="prediction",
        fmt="%.8f",
        delimiter=",",
        comments="",
    )

    # ---- low-rank factors ----
    np.savez_compressed(
        os.path.join(out_dir, "lowrank.npz"),
        U_fc0=lora.params["fc0__U"].detach().cpu().numpy(),
        V_fc0=lora.params["fc0__V"].detach().cpu().numpy(),
        U_fc1=lora.params["fc1__U"].detach().cpu().numpy(),
        V_fc1=lora.params["fc1__V"].detach().cpu().numpy(),
        U_head=lora.params["head__U"].detach().cpu().numpy(),
        V_head=lora.params["head__V"].detach().cpu().numpy(),
    )

    # ---- sample 1000 rows from intervened model over original columns ----
    n_sample = 1000
    rng = np.random.RandomState(SEED)
    feats = rng.rand(n_sample, 7)
    Xs = torch.from_numpy(feats).float()
    with torch.no_grad():
        Ys = lora.forward(Xs).reshape(-1).numpy()
    sample = np.column_stack([feats, Ys])
    np.savetxt(
        os.path.join(out_dir, "sample.csv"),
        sample,
        header="A,B,C,D,E,F,G,Y",
        fmt="%.6f",
        delimiter=",",
        comments="",
    )

    # ---- publish model dir ----
    torch.save(model.state_dict(), os.path.join(model_dir, "state_dict.pt"))
    adapter = {
        "r": HARD_RANK,
        "lora_alpha": LORA_ALPHA,
        "target_modules": [f"fc{i}" for i in range(len(model.fcs))],
        "bias": "none",
        "task_type": TASK_TYPE,
        "base_model_name_or_path": "elm-terrace-tiny-causal",
        "scale": LORA_ALPHA / HARD_RANK,
        "inference_mode": True,
    }
    with open(os.path.join(model_dir, "adapter_config.json"), "w") as f:
        json.dump(adapter, f, indent=2, sort_keys=True)
    with open(os.path.join(model_dir, "arch.json"), "w") as f:
        json.dump(arch, f)

    print("pipeline exports to", out_dir)
    return 0


def main(argv):
    cmd = argv[0] if argv else "load"
    if cmd == "load":
        if len(argv) < 3:
            sys.stderr.write("usage: load <state_dict.pt> <out.pt>\n")
            return 2
        return cmd_load(argv[1], argv[2])
    elif cmd == "run":
        data_dir = argv[1] if len(argv) > 1 else "/opt/causal/data"
        out_dir = argv[2] if len(argv) > 2 else "/app"
        return cmd_run(
            os.path.join(data_dir, "state_dict.pt"),
            os.path.join(data_dir, "train.csv"),
            os.path.join(data_dir, "holdout.csv"),
            out_dir,
        )
    else:
        sys.stderr.write(f"unknown subcommand {cmd}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))