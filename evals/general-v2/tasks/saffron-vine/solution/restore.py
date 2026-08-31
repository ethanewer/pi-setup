#!/usr/bin/env python3
"""
saffron-vine: recover a corrupted intent classifier via a LoRA lifecycle.

  python3 restore.py <casedir> <outdir>     (defaults: /app/case /app)

Pipeline:
  1) load the corrupted base + meta, recompute the degraded holdout accuracy;
  2) train a LoRA adapter (lora_A, lora_B) on fc2 ONLY, everything else frozen;
  3) persist the self-sufficient adapter directory (weights + config +
     feature spec) and the merged state dict;
  4) evaluate the merged model on the held-out split and write metrics.
"""
import argparse
import json
import os

import numpy as np
import safetensors.torch as st
import torch
import torch.nn as nn


class Net(nn.Module):
    def __init__(self, vocab, embed, hidden, out, pad_id):
        super().__init__()
        self.emb = nn.Embedding(vocab, embed, padding_idx=pad_id)
        self.fc1 = nn.Linear(embed, hidden)
        self.fc2 = nn.Linear(hidden, hidden)
        self.head = nn.Linear(hidden, out)

    def forward(self, ids):
        z = self.emb(ids).mean(dim=1)
        t1 = torch.tanh(self.fc1(z))
        t2 = torch.tanh(self.fc2(t1))
        return self.head(t2)


@torch.no_grad()
def accuracy(net, ids, labels, bs=1024):
    net.eval()
    correct = 0
    for i in range(0, len(labels), bs):
        logits = net(ids[i:i + bs])
        correct += (logits.argmax(dim=1) == labels[i:i + bs]).sum().item()
    return correct / len(labels)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("casedir", nargs="?", default="/app/case")
    ap.add_argument("outdir", nargs="?", default="/app")
    args = ap.parse_args()
    case, outdir = args.casedir, args.outdir
    os.makedirs(os.path.join(outdir, "adapter"), exist_ok=True)

    meta = json.load(open(os.path.join(case, "meta.json")))
    signals = json.load(open(os.path.join(case, "signals.json")))
    vocab_map = json.load(open(os.path.join(case, "vocab.json")))
    seed = int(meta["seed"])
    torch.manual_seed(seed)
    np.random.seed(seed)

    net = Net(meta["vocab_size"], meta["embed_dim"], meta["hidden_dim"],
              meta["num_classes"], meta["pad_id"])
    base = torch.load(os.path.join(case, "base_state.pt"), map_location="cpu")
    net.load_state_dict(base)
    net.eval()

    ids_tr = torch.from_numpy(np.load(os.path.join(case, "train_ids.npy"))).long()
    y_tr = torch.from_numpy(np.load(os.path.join(case, "train_labels.npy"))).long()
    ids_te = torch.from_numpy(np.load(os.path.join(case, "test_ids.npy"))).long()
    y_te = torch.from_numpy(np.load(os.path.join(case, "test_labels.npy"))).long()

    # ---- 1) degraded accuracy (recomputed) ---------------------------------
    degraded_acc = accuracy(net, ids_te, y_te)
    print("[1] degraded (corrupted base) holdout accuracy = %.4f" % degraded_acc)

    # ---- 2) train LoRA on fc2 only -----------------------------------------
    h = meta["hidden_dim"]
    r = int(meta["lora_rank"])
    alpha = float(meta["lora_alpha"])
    scale = alpha / r

    # precompute frozen features
    with torch.no_grad():
        z = net.emb(ids_tr).mean(dim=1)
        t1 = torch.tanh(net.fc1(z))

    # adapter params: A [r, in] (down), B [out, r] (up), B zero-initialised
    lora_A = nn.Parameter(torch.randn(r, h) * (0.05 / h ** 0.5))
    lora_B = nn.Parameter(torch.zeros(h, r))
    for p in net.parameters():
        p.requires_grad_(False)

    opt = torch.optim.Adam([lora_A, lora_B], lr=1e-2)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=1500)
    lossf = nn.CrossEntropyLoss()
    for ep in range(1500):
        base_out = t1 @ net.fc2.weight.T + net.fc2.bias
        logits = net.head(torch.tanh(base_out + scale * ((t1 @ lora_A.T) @ lora_B.T)))
        loss = lossf(logits, y_tr)
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        if ep % 300 == 0:
            print("[2] epoch %d loss %.4f" % (ep, loss.item()))
    print("[2] final loss %.4f" % loss.item())

    # ---- 3) persist the adapter directory + merged state --------------------
    A = lora_A.detach()
    B = lora_B.detach()
    st.save_file({"lora_A": A.contiguous(), "lora_B": B.contiguous()},
                 os.path.join(outdir, "adapter", "adapter_weights.safetensors"))

    adapter_config = {
        "rank": r,
        "lora_alpha": int(alpha) if float(alpha).is_integer() else alpha,
        "scale": scale,
        "target_module": "fc2",
        "case_id": meta["case_id"],
        "base_architecture": {
            "vocab_size": meta["vocab_size"],
            "embed_dim": meta["embed_dim"],
            "hidden_dim": meta["hidden_dim"],
            "num_classes": meta["num_classes"],
            "seq_len": meta["seq_len"],
            "pad_id": meta["pad_id"],
        },
    }
    with open(os.path.join(outdir, "adapter", "adapter_config.json"), "w") as f:
        json.dump(adapter_config, f, indent=2)

    feature_spec = {
        "vocab": vocab_map,
        "seq_len": meta["seq_len"],
        "pad_id": meta["pad_id"],
    }
    with open(os.path.join(outdir, "adapter", "feature_spec.json"), "w") as f:
        json.dump(feature_spec, f, indent=2)

    merged = {k: v.detach().clone() for k, v in base.items()}
    merged["fc2.weight"] = base["fc2.weight"] + scale * (B @ A)
    torch.save(merged, os.path.join(outdir, "adapter_merged.pt"))

    # ---- 4) evaluate the merged model deterministically ---------------------
    net.load_state_dict(merged)
    merged_acc = accuracy(net, ids_te, y_te)
    target = float(meta["target_accuracy"])
    metrics = {
        "case_id": meta["case_id"],
        "seed": seed,
        "pristine_holdout_accuracy": signals["pristine_holdout_accuracy"],
        "degraded_holdout_accuracy": round(degraded_acc, 4),
        "merged_holdout_accuracy": round(merged_acc, 4),
        "target_accuracy": target,
        "threshold_pass": bool(merged_acc >= target),
    }
    with open(os.path.join(outdir, "eval_metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print("[4] merged holdout accuracy = %.4f (target %.2f)" % (merged_acc, target))
    print("[4] threshold_pass =", metrics["threshold_pass"])


if __name__ == "__main__":
    main()
