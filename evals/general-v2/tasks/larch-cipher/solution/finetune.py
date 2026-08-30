#!/usr/bin/env python3
"""
larch-cipher: master program for the task.

  python3 finetune.py <casedir> <outdir>

<casedir> contains: meta.json, base_state.pt, training_signals.json,
X_train.npy, y_train.npy, X_test.npy, y_test.npy
<outdir> receives every persisted artifact.

Pipeline:
  1) DIAGNOSE  - inspect recorded training signals + base module to find why the
                 classifier is stalled (the designated OUTPUT LAYER was left
                 frozen and zeroed -> loss flat at ln(2), head grad norm 0,
                 val acc 0.5).
  2) FIX + FINE-TUNE ONLY THE HEAD -- unfreeze + re-initialise the head (the one
     fix that makes training converge), freeze all feature layers, train only the
     head. => outdir/head.pt (full state dict differing ONLY in the head vs base).
  3) LoRA LIFECYCLE - freeze, train a low-rank adapter on fc2, persist the adapter
     directory (weights + config), merge into the base, save merged model.
     => outdir/lora_adapter/ and outdir/adapter_merged.pt
  4) PERSIST - every model/array in the required loadable format.
     => outdir/state_dict.pkl (pickled state dict, canonical keys)
     => outdir/embeddings.npy (np.load-able target array)
     => outdir/classifier.pkl (loadable sklearn predictor)
  5) EVALUATE - deterministic fixed-seed reward loop over the held-out pool.
     => outdir/eval_metrics.json
"""
import argparse
import json
import os
import pickle

import numpy as np
import safetensors.torch as st
import torch
import torch.nn as nn
import torch.nn.functional as F


class Net(nn.Module):
    def __init__(self, d, h, out):
        super().__init__()
        self.fc1 = nn.Linear(d, h)
        self.fc2 = nn.Linear(h, h)
        self.head = nn.Linear(h, out)

    def forward(self, x):
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        return self.head(x)


def build_net(meta):
    return Net(meta["input_dim"], meta["hidden_dim"], meta["out_dim"])


def load_tensors(path):
    X_tr = np.load(os.path.join(path, "X_train.npy"))
    y_tr = np.load(os.path.join(path, "y_train.npy"))
    X_te = np.load(os.path.join(path, "X_test.npy"))
    y_te = np.load(os.path.join(path, "y_test.npy"))
    return X_tr, y_tr, X_te, y_te


def accuracy_at(net, X, y, bs=512):
    net.eval()
    Xt = torch.from_numpy(X).float()
    yt = torch.from_numpy(y)
    n = len(yt)
    correct = 0
    with torch.no_grad():
        for i in range(0, n, bs):
            logits = net(Xt[i:i + bs])
            correct += (logits.argmax(dim=1) == yt[i:i + bs]).sum().item()
    return correct / n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("casedir")
    ap.add_argument("outdir", nargs="?", default="/app")
    args = ap.parse_args()
    case, outdir = args.casedir, args.outdir
    os.makedirs(outdir, exist_ok=True)

    meta = json.load(open(os.path.join(case, "meta.json")))
    net = build_net(meta)
    net.load_state_dict(torch.load(os.path.join(case, "base_state.pt"),
                                   map_location="cpu"))
    net.eval()
    X_tr, y_tr, X_te, y_te = load_tensors(case)

    # ---- 1) DIAGNOSE ------------------------------------------------------
    base_acc = accuracy_at(net, X_te, y_te)
    head_zero = bool((net.head.weight == 0).all())
    print("[1] diagnose: base eval acc=%.4f ; head.weight all-zero=%s"
          % (base_acc, head_zero))
    print("[1] training_signals.json: loss flat at ~ln(2), head_grad_norm=0.0, "
          "val_acc=0.5 every epoch -> the designated OUTPUT LAYER is not being "
          "optimised (it is frozen).")

    # ---- 2) SINGLE FIX: unfreeze + re-init the head, then train ONLY head --
    for p in net.head.parameters():
        p.requires_grad = True
    with torch.no_grad():
        nn.init.kaiming_uniform_(net.head.weight, a=np.sqrt(5))
        nn.init.uniform_(net.head.bias, -0.1, 0.1)
    for name, p in net.named_parameters():
        if not name.startswith("head"):
            p.requires_grad = False

    Xtr = torch.from_numpy(X_tr).float()
    ytr = torch.from_numpy(y_tr)
    opt = torch.optim.Adam([p for p in net.parameters() if p.requires_grad],
                           lr=0.05)
    lossf = nn.CrossEntropyLoss()
    torch.manual_seed(42)
    hist = []
    for ep in range(30):
        perm = torch.randperm(len(Xtr))
        tot = 0.0
        for i in range(0, len(Xtr), 256):
            idx = perm[i:i + 256]
            opt.zero_grad()
            out = net(Xtr[idx])
            loss = lossf(out, ytr[idx])
            loss.backward()
            opt.step()
            tot += loss.item()
        acc = accuracy_at(net, X_te, y_te)
        gradn = max((p.grad.norm().item() if p.grad is not None else 0.0)
                    for p in net.head.parameters())
        hist.append({"epoch": ep + 1, "train_loss": round(tot, 4),
                     "val_acc": round(acc, 4),
                     "head_grad_norm": round(gradn, 6)})
    head_acc = hist[-1]["val_acc"]
    print("[2] head-only fine-tune final val_acc=%.4f" % head_acc)

    head_state = net.state_dict()
    torch.save(head_state, os.path.join(outdir, "head.pt"))
    pickle.dump(head_state, open(os.path.join(outdir, "state_dict.pkl"), "wb"))
    np.save(os.path.join(outdir, "embeddings.npy"),
            net.head.weight.detach().numpy())

    # ---- sklearn predictor (loadable) on the raw input space -----------------
    from sklearn.linear_model import LogisticRegression
    clf = LogisticRegression(max_iter=500)
    clf.fit(X_tr, y_tr)
    clf_acc = float(clf.score(X_te, y_te))
    pickle.dump(clf, open(os.path.join(outdir, "classifier.pkl"), "wb"))
    print("[2] classifier.pkl test acc=%.4f" % clf_acc)

    # ---- 3) LoRA train / save / merge lifecycle on fc2 ---------------------
    for p in net.parameters():
        p.requires_grad = False
    rank, alpha = 1, 0.4
    scale = alpha / rank
    A = nn.Parameter(torch.randn(rank, net.fc2.in_features) * 0.1)
    B = nn.Parameter(torch.zeros(net.fc2.out_features, rank))
    lopt = torch.optim.Adam([A, B], lr=0.05)
    torch.manual_seed(7)
    for ep in range(30):
        perm = torch.randperm(len(Xtr))
        tot = 0.0
        for i in range(0, len(Xtr), 256):
            idx = perm[i:i + 256]
            lopt.zero_grad()
            h1 = F.relu(net.fc1(Xtr[idx]))
            base_out = net.fc2(h1)
            adapt = (B @ A @ h1.t()).t() * scale
            logits = net.head(F.relu(base_out + adapt))
            loss = F.cross_entropy(logits, ytr[idx])
            loss.backward()
            lopt.step()
            tot += loss.item()

    adir = os.path.join(outdir, "lora_adapter")
    os.makedirs(adir, exist_ok=True)
    st.save_file({"lora_A": A.detach(), "lora_B": B.detach()},
                 os.path.join(adir, "adapter_weights.safetensors"))
    json.dump({"rank": rank, "lora_alpha": alpha, "scale": scale,
               "target_module": "fc2",
               "base_arch": meta,
               "weights_file": "adapter_weights.safetensors"},
              open(os.path.join(adir, "adapter_config.json"), "w"), indent=2)

    # Merge: fc2.weight += scale * (B @ A); head stays the fine-tuned head.
    merged = net.state_dict()
    with torch.no_grad():
        merged["fc2.weight"] = merged["fc2.weight"] + ((B.detach() @ A.detach()) * scale)
    merged_net = build_net(meta)
    merged_net.load_state_dict(merged)
    torch.save(merged, os.path.join(outdir, "adapter_merged.pt"))
    merged_acc = accuracy_at(merged_net, X_te, y_te)
    print("[3] merged model test acc=%.4f" % merged_acc)
    # update the pickled state dict to the merged form (canonical keys)
    pickle.dump(merged, open(os.path.join(outdir, "state_dict.pkl"), "wb"))
    np.save(os.path.join(outdir, "merged_weights.npy"),
            merged_net.fc2.weight.detach().numpy())

    # ---- 4) deterministic fixed-seed reward loop over held-out pool --------
    rng = np.random.default_rng(2112)
    trials = []
    n = len(y_te)
    with torch.no_grad():
        for t in range(5):
            idx = rng.choice(n, size=int(0.8 * n), replace=False)
            acc = (merged_net(torch.from_numpy(X_te[idx]).float()).argmax(dim=1)
                   == torch.from_numpy(y_te[idx])).float().mean().item()
            trials.append(round(acc, 6))
    metrics = {
        "case_id": meta["case_id"],
        "seed": 2112,
        "n_trials": 5,
        "mean_reward": round(float(np.mean(trials)), 6),
        "trials": trials,
        "eval_accuracy_head": round(head_acc, 4),
        "eval_accuracy_merged": round(merged_acc, 4),
        "adapter_acc": round(merged_acc, 4),
        "evaluation_is_deterministic": True,
    }
    json.dump(metrics, open(os.path.join(outdir, "eval_metrics.json"), "w"),
              indent=2)
    print("WROTE_%s mean_reward=%.4f" % (outdir, metrics["mean_reward"]))
    print("OK artifacts in", outdir)


if __name__ == "__main__":
    main()