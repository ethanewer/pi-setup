#!/usr/bin/env python3
"""Distributed 2-stage pipeline-parallel (AFAB) training of the reference
tiny LLaMA-like model.

  rank0 -> stage0: embed + blocks.{0,1,2}
  rank1 -> stage1: blocks.{3,4,5} + head.ln + head.out

Implements the all-forward / all-backward schedule with 2 microbatches and
must reproduce the canonical single-process reference (forward, loss,
gradients, SGD) exactly. Launch: torchrun --standalone --nnodes=1
--nproc_per_node=2 main.py
"""
import os
import sys
import json

import torch
import torch.nn.functional as F
import torch.distributed as dist

sys.path.insert(0, "/app")
import reference
from reference import build_params, block_forward, rms

torch.set_num_threads(1)
dist.init_process_group(backend="gloo")
rank = dist.get_rank()
world = dist.get_world_size()

assert world == 2, f"expected 2 ranks, got {world}"
stage0 = rank == 0

LR = 0.05
SEED = 20260407
STEPS = 4
M = 2          # microbatches
BS = 2         # microbatch batch size
SEQ = 16

VOCAB = reference.VOCAB
DMODEL = reference.DMODEL


def in_stage0(k):
    if k == "embed":
        return True
    if k.startswith("blocks."):
        return int(k.split(".")[1]) in (0, 1, 2, 3)
    return False


def in_stage1(k):
    if k.startswith("blocks."):
        return int(k.split(".")[1]) in (3, 4, 5)
    if k.startswith("head."):
        return True
    return False


# ---- build shards (canonical deterministic init) ----
fullp = build_params(seed=SEED)
keys = sorted([k for k in fullp if (in_stage0(k) if stage0 else in_stage1(k))])
params = {k: fullp[k].detach().clone().requires_grad_(True) for k in keys}


def forward_stage(inp):
    """Token ids (stage0) -> hidden; hidden (stage1) -> logits."""
    if stage0:
        h = params["embed"][inp]
        for i in (0, 1, 2):
            h = block_forward(params, f"blocks.{i}", h)
        return h
    h = inp
    for i in (3, 4, 5):
        h = block_forward(params, f"blocks.{i}", h)
    h = rms(h, params["head.ln"])
    return h @ params["head.out"].t()


def ce_loss(logits, mb_tok):
    lg = logits[:, :-1, :].reshape(-1, VOCAB)
    lb = mb_tok[:, 1:].reshape(-1)
    return F.cross_entropy(lg, lb)


tokens = torch.load("/app/data/tokens.pt")   # (5, 4, 16)

losses_per_step = []   # [[m0, m1], ...] per global step, measured at stage1
last_grads = {}        # engine mean gradient at the final step (owned keys)
w_before = {}          # owned weights at the start of the final step

h_shape = (BS, SEQ, DMODEL)
for s in range(STEPS):
    step_tok = tokens[s]
    step_losses = []
    h_store = []
    if stage0:
        # --- forward phase: send hidden for each microbatch (keep local graph) ---
        for m in range(M):
            mb_tok = step_tok[m * BS:(m + 1) * BS]
            h = forward_stage(mb_tok)
            # NOTE: stage boundary — hidden sent downstream must be (2,16,32)
            dist.send(torch.cat([h.detach(), h.detach()], dim=1), dst=1)
            h_store.append(h)
    else:
        # --- forward phase: receive hidden, run tail, record micro losses ---
        for m in range(M):
            buf = torch.empty(*h_shape)
            dist.recv(buf, src=0)
            h = buf.requires_grad_(True)
            mb_tok = step_tok[m * BS:(m + 1) * BS]
            logits = forward_stage(h)
            loss_m = ce_loss(logits, mb_tok)
            step_losses.append(loss_m.item())
            h_store.append(h)
    losses_per_step.append(step_losses)
    dist.barrier()

    # --- backward phase ---
    if stage0:
        for m in range(M):
            buf = torch.empty(*h_shape)
            dist.recv(buf, src=1)
            torch.autograd.backward(h_store[m], buf)
    else:
        for m in range(M):
            h = h_store[m]
            mb_tok = step_tok[m * BS:(m + 1) * BS]
            logits = forward_stage(h)
            loss_m = ce_loss(logits, mb_tok)
            loss_m.backward()
            dist.send(h.grad, dst=0)
    dist.barrier()

    # --- average gradients over microbatches; SGD update on OWN params ---
    for k, p in params.items():
        if p.grad is None:
            continue
        gavg = p.grad  # TODO: average over microbatches?
        if s == STEPS - 1:
            last_grads[k] = gavg.detach().clone()
            w_before[k] = p.data.detach().clone()
        with torch.no_grad():
            p.data.sub_(LR * gavg)
        p.grad = None
    dist.barrier()

# --- export stage1's measured losses + final-step verification data ---
if not stage0:
    os.makedirs("/app/engine/out", exist_ok=True)
    with open("/app/engine/out/_losses.json", "w") as f:
        json.dump(losses_per_step, f)
dist.barrier()

out_dir = "/app/engine/out"
os.makedirs(out_dir, exist_ok=True)
shard_save = {k: p.detach().cpu() for k, p in params.items()}
if rank == 0:
    torch.save(shard_save, os.path.join(out_dir, "w_stage0.pt"))
else:
    torch.save(shard_save, os.path.join(out_dir, "w_stage1.pt"))
    torch.save({k: v.detach().cpu() for k, v in w_before.items()},
               os.path.join(out_dir, "_w1_before.pt"))
    torch.save({k: v.detach().cpu() for k, v in last_grads.items()},
               os.path.join(out_dir, "_g1.pt"))
dist.barrier()

# --- gradient equivalence (rank0): engine mean final-step gradients vs
#     reference.grads on the merged weights at the start of the final step ---
grad_equiv = None
if rank == 0:
    w1_before = torch.load(os.path.join(out_dir, "_w1_before.pt"))
    g1 = torch.load(os.path.join(out_dir, "_g1.pt"))
    full_before = {k: (w_before[k] if k in w_before else w1_before[k]).clone()
                   for k in sorted(fullp.keys())}
    eng_grads = {k: (last_grads[k] if k in last_grads else g1[k]).clone()
                 for k in sorted(fullp.keys())}
    refg, _ = reference.grads(full_before, tokens[STEPS - 1])
    max_abs = 0.0
    max_rel = 0.0
    for k in sorted(fullp.keys()):
        absd = (eng_grads[k] - refg[k]).abs().max().item()
        reld = absd / max(refg[k].abs().max().item(), 1e-8)
        max_abs = max(max_abs, absd)
        max_rel = max(max_rel, reld)
    grad_equiv = {
        "max_abs_diff": round(max_abs, 6),
        "max_rel_diff": round(max_rel, 6),
        "num_tensors_compared": len(fullp),
    }

# --- rank0: final loss on merged saved weights, then write report.json ---
if rank == 0:
    with open(os.path.join(out_dir, "_losses.json")) as f:
        losses_per_step = json.load(f)
    w1 = torch.load(os.path.join(out_dir, "w_stage1.pt"))
    w0 = torch.load(os.path.join(out_dir, "w_stage0.pt"))
    full_final = {k: (w0[k] if k in w0 else w1[k]).clone() for k in sorted(fullp.keys())}
    final_loss = reference.loss(full_final, tokens[STEPS - 1]).item()

    report = {
        "flavor": "main",
        "world": {"pipeline_stages": 2, "tensor_parallel_size": 1, "total_ranks": 2,
                  "stage_ranks": {"stage0": [0], "stage1": [1]}},
        "model": {"vocab": VOCAB, "d_model": DMODEL, "n_heads": reference.N_HEADS,
                  "head_dim": reference.HEAD_DIM, "layers": reference.N_LAYERS},
        "layers_per_stage": [3, 3],
        "training": {"steps": STEPS, "microbatches": M, "microbatch_batch_size": BS,
                     "seq_len": SEQ, "optimizer": "sgd", "lr": LR, "init_seed": SEED},
        "per_step_microbatch_losses": [[round(v, 4) for v in row] for row in losses_per_step],
        "final_loss": round(final_loss, 4),
        "gradient_equivalence": grad_equiv,
        "outputs": {"weights": ["/app/engine/out/w_stage0.pt", "/app/engine/out/w_stage1.pt"]},
    }
    with open(os.path.join(out_dir, "report.json"), "w") as f:
        json.dump(report, f, indent=2)
    for tmp in ("_w1_before.pt", "_g1.pt", "_losses.json"):
        try:
            os.remove(os.path.join(out_dir, tmp))
        except OSError:
            pass

dist.barrier()
if rank == 0:
    print("engine finished OK")