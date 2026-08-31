#!/usr/bin/env python3
"""Fixture generator for saffron-vine.

Produces a degraded on-device intent-classifier scenario:

  * a small token-sequence classifier  emb -> mean-pool -> fc1 (tanh) ->
    fc2 (tanh) -> head  is trained to its label-noise ceiling,
  * a failed checkpoint-restore step zeroes fc2.weight, which collapses
    holdout accuracy to chance,
  * the shipped base_state.pt contains the QUANTIZED model; signals.json
    records the pristine and degraded holdout accuracies.

Usage: python3 gen.py <outdir> <case_id> <seed> [vocab] [embed] [hidden]
                      [seq_len] [quant_step]
"""
import json
import os
import sys

import numpy as np
import torch
import torch.nn as nn

torch.set_num_threads(1)


def build_model(vocab, embed, hidden, out):
    return nn.Sequential(
        nn.Embedding(vocab, embed, padding_idx=0),
        MeanPool(),
        nn.Linear(embed, hidden),
        nn.Tanh(),
        nn.Linear(hidden, hidden),
        nn.Tanh(),
        nn.Linear(hidden, out),
    )


class MeanPool(nn.Module):
    def forward(self, x):
        return x.mean(dim=1)


def keys_of(m):
    return {
        "emb": 0, "fc1": 2, "fc2": 4, "head": 6,
    }


def main():
    qstep = 0.0
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    vocab = int(sys.argv[4]) if len(sys.argv) > 4 else 42
    embed = int(sys.argv[5]) if len(sys.argv) > 5 else 16
    hidden = int(sys.argv[6]) if len(sys.argv) > 6 else 24
    seq_len = int(sys.argv[7]) if len(sys.argv) > 7 else 8

    n_train, n_test, flip = 900, 400, 0.06
    out_dim = 2

    g = np.random.default_rng(seed)
    half = (vocab - 1) // 2  # tokens 1..half => class0-ish, half+1.. => class1

    def make_split(n):
            # token streams biased toward one half of the vocabulary
        tok0 = g.integers(1, half + 1, size=(n, seq_len))
        tok1 = g.integers(half + 1, vocab, size=(n, seq_len))
        pick0 = g.random((n, seq_len)) < 0.80
        pick1 = g.random((n, seq_len)) < 0.80
        tok0b = np.where(pick0, tok0, tok1)
        tok1b = np.where(pick1, tok1, tok0)
        X = np.concatenate([tok0b, tok1b]).astype(np.int64)
        y = np.concatenate([np.zeros(n, np.int64), np.ones(n, np.int64)])
        fl = g.random(len(y)) < flip
        y[fl] = 1 - y[fl]
        idx = g.permutation(len(y))
        return X[idx], y[idx]

    X_tr, y_tr = make_split(n_train)
    X_te, y_te = make_split(n_test)

    torch.manual_seed(seed + 101)
    model = build_model(vocab, embed, hidden, out_dim)
    # Planted embedding geometry: tokens 1..half point along +u, tokens
    # half+1.. point along -u, so the class signal lives in the mean-pooled
    # embedding and generalizes instead of memorizing token identities.
    with torch.no_grad():
        uvec = torch.randn(embed)
        uvec = uvec / uvec.norm()
        table = torch.randn(vocab, embed) * 0.25
        table[1:half + 1] += uvec * 0.8
        table[half + 1:] -= uvec * 0.8
        table[0].zero_()
        model[0].weight.copy_(table)
    model[0].weight.requires_grad_(False)

    Xt = torch.from_numpy(X_tr)
    yt = torch.from_numpy(y_tr)
    opt = torch.optim.Adam([p for p in model.parameters() if p.requires_grad],
                           lr=8e-3)
    lossf = nn.CrossEntropyLoss()

    @torch.no_grad()
    def acc(m, X, y):
        pred = m(torch.from_numpy(X)).argmax(dim=1).numpy()
        return float((pred == y).mean())

    best = (-1.0, None)
    for ep in range(1000):
        opt.zero_grad()
        loss = lossf(model(Xt), yt)
        loss.backward()
        opt.step()
        if (ep + 1) % 10 == 0:
            a = acc(model, X_te, y_te)
            if a > best[0]:
                best = (a, {k: v.detach().clone()
                            for k, v in model.state_dict().items()})
    model.load_state_dict(best[1])

    pristine_test = acc(model, X_te, y_te)

    # ---- corrupt fc2.weight (the failed checkpoint restore) -----------------
    sd = {k: v.detach().clone() for k, v in model.state_dict().items()}
    sd["4.weight"] = torch.zeros_like(sd["4.weight"])
    model.load_state_dict(sd)
    degraded_test = acc(model, X_te, y_te)

    # ship the QUANTIZED state (canonical key names) as the base fixture
    sd2 = {}
    for k, v in sd.items():
        i = int(k.split(".")[0])
        name = {0: "emb", 2: "fc1", 4: "fc2", 6: "head"}[i] + "." + k.split(".", 1)[1]
        sd2[name] = v
    torch.save(sd2, os.path.join(outdir, "base_state.pt"))

    vocab_map = {"<pad>": 0}
    for t in range(1, vocab):
        vocab_map["tok%03d" % t] = t

    meta = {
        "case_id": case_id,
        "seed": seed,
        "vocab_size": vocab,
        "embed_dim": embed,
        "hidden_dim": hidden,
        "num_classes": out_dim,
        "seq_len": seq_len,
        "pad_id": 0,
        "lora_rank": 12,
        "lora_alpha": 24,
        "target_accuracy": 0.86,
        "degradation": "fc2.weight zeroed by a failed checkpoint restore",
        "architecture": "emb->meanpool->fc1(tanh)->fc2(tanh)->head",
        "lora_target_module": "fc2",
    }
    signals = {
        "pristine_holdout_accuracy": round(pristine_test, 4),
        "degraded_holdout_accuracy": round(degraded_test, 4),
        "note": ("a failed checkpoint restore zeroed fc2.weight and degraded "
                 "the holdout accuracy; recover it with a low-rank adapter "
                 "trained on fc2 only"),
    }

    np.save(os.path.join(outdir, "train_ids.npy"), X_tr)
    np.save(os.path.join(outdir, "train_labels.npy"), y_tr)
    np.save(os.path.join(outdir, "test_ids.npy"), X_te)
    np.save(os.path.join(outdir, "test_labels.npy"), y_te)
    with open(os.path.join(outdir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(outdir, "signals.json"), "w") as f:
        json.dump(signals, f, indent=2)
    with open(os.path.join(outdir, "vocab.json"), "w") as f:
        json.dump(vocab_map, f, indent=2)
    print("%s: pristine=%.4f degraded=%.4f" % (case_id, pristine_test,
                                               degraded_test))


if __name__ == "__main__":
    main()
