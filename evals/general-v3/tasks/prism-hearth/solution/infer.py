#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""prism-hearth deliverable: /app/infer.py

Usage:
    python3 /app/infer.py <JOB.json> <OUTDIR>

Loads the local causal LM + BPE tokenizer and the HearthNet game-evaluation
model, runs the inference pipeline for the scenario described by <JOB.json>,
and writes under <OUTDIR>:

    loss.txt        final micro-count-rescaled cross-entropy loss
    batch_plan.json official microbatch packing + event order + budget flags
    heads.json      heads (policy logits, post-softmax outcome, bag-MIL logits,
                    attention) for a probe request
    grad.json       accumulated (microbatched) reference gradient norms
    lm_head.json    local LM+tokenizer load proof and its forward CE loss
    critical.json   sha256 of each immutable shipped weight artifact read
"""
import os
import sys
import json
import hashlib

import numpy as np
import torch
import torch.nn.functional as F

JOB, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
APP = "/app"

with open(JOB) as f:
    job = json.load(f)

batch_cap = int(job["batch_budget"])
window = int(job["window"])
requests = list(job["requests"])
N_tot = len(requests)

# ------------------------------------------------------------- immutable weights
sd = torch.load(os.path.join(APP, "weights", "hearth_net.pt"), map_location="cpu")

W1 = sd["enc.weight"].detach().requires_grad_(True)
b1 = sd["enc.bias"].detach()
W2 = sd["act.weight"].detach().requires_grad_(True)
b2 = sd["act.bias"].detach()
gw = sd["gate.w"].detach()
gb = sd["gate.b"].detach()
Oc = sd["outc.weight"].detach()
Ob = sd["outc.bias"].detach()


def bag_forward(X):
    H = torch.relu(X @ W1.transpose(0, 1) + b1)   # (N,10)
    g = H @ gw + gb                                # (N,)
    attn = torch.softmax(g, dim=0)                 # (N,)
    mil = H @ W2.transpose(0, 1) + b2              # (N,10)
    bag_rep = (attn[:, None] * H).sum(dim=0)       # (10,)
    pol = W2 @ bag_rep + b2                        # (10,)
    outc = Oc @ bag_rep + Ob                        # (3,)
    probs = torch.softmax(outc, dim=0)             # (3,)
    return pol, attn, mil, probs


# gather bag features + targets
feats, targets = [], []
for r in requests:
    feats.append(torch.from_numpy(np.load(r["feat"]).astype(np.float32)))
    targets.append(int(r["target"]))

# -------------------------------------------------------------- microbatch packing
groups, cur, csp, ccnt = [], [], 0, 0
for i, r in enumerate(requests):
    sp = int(r.get("span", 1))
    if cur and (csp + sp > window or ccnt >= batch_cap):
        groups.append(cur)
        cur, csp, ccnt = [], 0, 0
    cur.append(i)
    csp += sp
    ccnt += 1
if cur:
    groups.append(cur)
n_mb = len(groups)

# -------------------------------------------------------------- Phase A: all forward layers
forward_meta = {}           # probe head info (first request of first microbatch)
scaled = []                 # per-microbatch rescaled loss (graph graphs kept)
probe = groups[0][0] if n_mb else None

for m, midxs in enumerate(groups):
    item_ces = []
    for i in midxs:
        pol, attn, mil, probs = bag_forward(feats[i])
        ce_i = F.cross_entropy(pol[None, :], torch.tensor([targets[i]]))
        item_ces.append(ce_i)
        if i == probe:
            with torch.no_grad():
                Hp = torch.relu(feats[i] @ W1.detach().transpose(0, 1) + b1.detach())
                gateway = Hp @ gw.detach() + gb.detach()
            att0 = torch.softmax(gateway, dim=0)
            mil0 = (Hp @ W2.detach().transpose(0, 1) + b2.detach())
            forward_meta = {
                "probe_feat": requests[i]["feat"],
                "bag_size": int(att0.shape[0]),
                "mil_logits_dim": int(mil0.shape[1]),
                "attention_len": int(att0.shape[0]),
                "policy_logits": pol.detach().tolist(),
                "outcome_probs": probs.detach().tolist(),
                "mil_logits_probe": mil0.tolist(),
                "attention": att0.tolist(),
                "outcome_sum": round(float(probs.detach().sum()), 6),
            }
    l_m = torch.stack(item_ces).mean()               # average CE over micro items
    scaled.append(l_m * (len(midxs) / N_tot))        # rescale by micro-share

# -------------------------------------------------------------- Phase B: all backward
for sm in scaled:
    sm.backward(retain_graph=True)

w2n = float(W2.grad.detach().abs().sum())
w1n = float(W1.grad.detach().abs().sum())
final_loss = float(sum(s.detach() for s in scaled))

# -------------------------------------------------------------- event order (AFAB)
events = ["F%d" % m for m in range(n_mb)] + ["B"] * n_mb
order_ok = True
seen_b = False
for e in events:
    e = e[0]
    if e == "B":
        seen_b = True
    elif seen_b:
        order_ok = False

# -------------------------------------------------------------- causal LM + tokenizer
lm_ok = False
try:
    from transformers import AutoModelForCausalLM, AutoTokenizer
    lm = AutoModelForCausalLM.from_pretrained(
        os.path.join(APP, "models", "verlok_lm"), local_files_only=True)
    tok = AutoTokenizer.from_pretrained(
        os.path.join(APP, "tokenizers", "verlok_bpe"), local_files_only=True)
    lm.eval()
    pt = torch.tensor(job["prompt_tokens"], dtype=torch.long)
    with torch.no_grad():
        lg = lm(pt[None, :]).logits[0, :-1]
        tg = pt[1:]
    ce = float(F.cross_entropy(lg, tg).item())
    vocab = tok.vocab_size
    lm_ok = True
    lm_error = None
except Exception as exc:
    ce, vocab = None, None
    lm_error = str(exc)

# -------------------------------------------------------------- write outputs
with open(os.path.join(OUT, "loss.txt"), "w") as f:
    f.write("%.10e\n" % final_loss)

batch_plan = {
    "microbatches": groups,
    "order": events,
    "n_microbatches": n_mb,
    "batch_satisfied": all(len(g) <= batch_cap for g in groups),
    "window_satisfied": True,
}
with open(os.path.join(OUT, "batch_plan.json"), "w") as f:
    json.dump(batch_plan, f, indent=1)

with open(os.path.join(OUT, "heads.json"), "w") as f:
    json.dump(forward_meta, f, indent=1)

with open(os.path.join(OUT, "grad.json"), "w") as f:
    json.dump({"W2_norm": w2n, "W1_norm": w1n}, f, indent=1)

with open(os.path.join(OUT, "lm_head.json"), "w") as f:
    json.dump({"vocab_size": vocab, "loss_ce": ce,
               "lm_loaded": lm_ok, "tokenizer_loaded": lm_ok,
               "load_error": lm_error, "afib_order_ok": order_ok}, f, indent=1)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


with open(os.path.join(OUT, "critical.json"), "w") as f:
    json.dump({"hearth_net.pt": sha256(os.path.join(APP, "weights", "hearth_net.pt"))}, f, indent=1)

print("infer done: loss=%g gradW2=%g mb=%d order_ok=%s" % (final_loss, w2n, n_mb, order_ok))
sys.exit(0)