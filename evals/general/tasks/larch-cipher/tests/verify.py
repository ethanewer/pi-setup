#!/usr/bin/env python3
"""Independent verifier for larch-cipher.

  python3 verify.py <casedir> <outdir>

Re-constructs the classifier solely from the fixture's meta.json / base_state.pt
(never from the agent's code), then validates every persisted artifact in
<outdir>. Exits 0 only when all checks pass.
Thresholds sit well below the reproducible band of the reference pipeline
(head/merged/mean_reward ~0.91-0.93) so honest solutions pass with margin.

This verifier must cover every declared deliverable. For the visible case
outdir == /app, so each corresponds one-to-one to the canonical paths:
    /app/head.pt
    /app/adapter_merged.pt
    /app/state_dict.pkl
    /app/eval_metrics.json
    /app/embeddings.npy
    /app/classifier.pkl
    /app/lora_adapter/adapter_config.json
    /app/lora_adapter/adapter_weights.safetensors
On the hidden re-runs outdir is a scratch dir and the same files are checked
there by the same code below.
"""
import json
import os
import pickle
import sys

import numpy as np
import safetensors.torch as st
import torch
import torch.nn as nn
import torch.nn.functional as F

HEAD_MIN = 0.85
MERGED_MIN = 0.84
REWARD_MIN = 0.82


class Net(nn.Module):
    def __init__(self, meta):
        super().__init__()
        self.fc1 = nn.Linear(meta["input_dim"], meta["hidden_dim"])
        self.fc2 = nn.Linear(meta["hidden_dim"], meta["hidden_dim"])
        self.head = nn.Linear(meta["hidden_dim"], meta["out_dim"])

    def forward(self, x):
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        return self.head(x)


def acc_at(net, X, y):
    net.eval()
    Xt = torch.from_numpy(X).float()
    yt = torch.from_numpy(y)
    n = len(yt)
    c = 0
    with torch.no_grad():
        for i in range(0, n, 512):
            c += int((net(Xt[i:i + 512]).argmax(dim=1) == yt[i:i + 512]).sum())
    return c / n


def main(casedir, outdir):
    ok = []

    meta = json.load(open(os.path.join(casedir, "meta.json")))
    base_state = torch.load(os.path.join(casedir, "base_state.pt"),
                            map_location="cpu", weights_only=True)
    X_te = np.load(os.path.join(casedir, "X_test.npy"))
    y_te = np.load(os.path.join(casedir, "y_test.npy"))
    keys = set(base_state.keys())

    base_net = Net(meta)
    base_net.load_state_dict(base_state)
    base_acc = acc_at(base_net, X_te, y_te)
    ok.append("base_acc=%.3f" % base_acc)

    # ---- head.pt ----------------------------------------------------------
    hp = os.path.join(outdir, "head.pt")
    hs = None
    if os.path.exists(hp):
        hs = torch.load(hp, map_location="cpu", weights_only=False)
        if set(hs.keys()) == keys:
            ok.append("head.pt keys match base")
            frozen_ok = True
            for name in keys:
                if name.startswith(("fc1", "fc2")):
                    if not torch.equal(hs[name], base_state[name]):
                        frozen_ok = False
                        ok.append("FAIL head.pt changed frozen %s" % name)
            if frozen_ok:
                ok.append("head.pt frozen layers identical to base")
            if bool((hs["head.weight"] != 0).any()) and \
                    bool((hs["head.bias"] != 0).any()):
                ok.append("head params nonzero (fix applied)")
            else:
                ok.append("FAIL head still frozen/zero")
            hnet = Net(meta)
            hnet.load_state_dict(hs)
            ha = acc_at(hnet, X_te, y_te)
            ok.append("head_acc=%.3f" % ha)
            if ha < HEAD_MIN:
                ok.append("FAIL head_acc<%.2f" % HEAD_MIN)
        else:
            ok.append("FAIL head.pt key mismatch")
    else:
        ok.append("FAIL missing head.pt")

    # ---- LoRA adapter directory + adapter_merged.pt -----------------------
    adir = os.path.join(outdir, "lora_adapter")
    cfgf = os.path.join(adir, "adapter_config.json")
    wgtf = os.path.join(adir, "adapter_weights.safetensors")
    merged_f = os.path.join(outdir, "adapter_merged.pt")
    if os.path.exists(cfgf) and os.path.exists(wgtf) and os.path.exists(merged_f):
        cfg = json.load(open(cfgf))
        sw = st.load_file(wgtf)
        if set(sw.keys()) >= {"lora_A", "lora_B"}:
            A, B = sw["lora_A"], sw["lora_B"]
            if A.shape[0] != B.shape[1] or A.shape[0] == 0:
                ok.append("FAIL lora rank mismatch")
            else:
                r = int(cfg.get("rank", A.shape[0]))
                scale = float(cfg.get("scale", 1.0))
                if r != A.shape[0]:
                    scale = scale * (A.shape[0] / r)
                delta = (B @ A) * scale
                ms = torch.load(merged_f, map_location="cpu", weights_only=False)
                if set(ms.keys()) == keys:
                    ok.append("adapter_merged.pt keys match base")
                    if torch.allclose(ms["fc2.weight"],
                                      base_state["fc2.weight"] + delta,
                                      atol=1e-4):
                        ok.append("merged.fc2==base.fc2+LoRA (merge correct)")
                    else:
                        ok.append("FAIL merged.fc2 != base.fc2+LoRA")
                    if hs is not None and torch.equal(ms["head.weight"],
                                                      hs["head.weight"]) and \
                            torch.equal(ms["head.bias"], hs["head.bias"]):
                        ok.append("merged.head == fine-tuned head")
                    mnet = Net(meta)
                    mnet.load_state_dict(ms)
                    ma = acc_at(mnet, X_te, y_te)
                    ok.append("merged_acc=%.3f" % ma)
                    if ma < MERGED_MIN:
                        ok.append("FAIL merged acc<%.2f" % MERGED_MIN)
                else:
                    ok.append("FAIL adapter_merged keys mismatch")
        else:
            ok.append("FAIL adapter_weights missing lora_A/B")
    else:
        ok.append("FAIL lora_adapter/ or adapter_merged.pt incomplete")

    # ---- state_dict.pkl -----------------------------------------------------
    sp = os.path.join(outdir, "state_dict.pkl")
    if os.path.exists(sp):
        try:
            sd = pickle.load(open(sp, "rb"))
            if isinstance(sd, dict) and set(sd.keys()) == keys and \
                    sd["fc1.weight"].shape == (meta["hidden_dim"],
                                               meta["input_dim"]):
                ok.append("state_dict.pkl canonical state dict (embedding key)")
            else:
                ok.append("FAIL state_dict.pkl not canonical")
        except Exception as e:
            ok.append("FAIL state_dict.pkl %s" % str(e)[:80])
    else:
        ok.append("FAIL missing state_dict.pkl")

    # ---- embeddings.npy -----------------------------------------------------
    nef = os.path.join(outdir, "embeddings.npy")
    if os.path.exists(nef):
        try:
            arr = np.load(nef)
            if arr.ndim >= 1 and arr.size and bool(np.isfinite(arr).all()):
                ok.append("embeddings.npy loads %s" % (arr.shape,))
            else:
                ok.append("FAIL embeddings.npy empty/nonfinite")
        except Exception as e:
            ok.append("FAIL embeddings.npy %s" % str(e)[:60])
    else:
        ok.append("FAIL missing embeddings.npy")

    # ---- classifier.pkl -----------------------------------------------------
    cpf = os.path.join(outdir, "classifier.pkl")
    if os.path.exists(cpf):
        try:
            clf = pickle.load(open(cpf, "rb"))
            if hasattr(clf, "predict"):
                p = np.asarray(clf.predict(X_te))
                ca = float(np.mean(p == y_te))
                ok.append("classifier.pkl predicts (acc %.3f)" % ca)
            else:
                ok.append("FAIL classifier.pkl no .predict")
        except Exception as e:
            ok.append("FAIL classifier.pkl %s" % str(e)[:80])
    else:
        ok.append("FAIL missing classifier.pkl")

    # ---- eval_metrics.json ---------------------------------------------------
    emf = os.path.join(outdir, "eval_metrics.json")
    if os.path.exists(emf):
        m = json.load(open(emf))
        mr = float(m.get("mean_reward", -1.0))
        ok.append("mean_reward=%.3f" % mr)
        if mr < REWARD_MIN:
            ok.append("FAIL mean_reward<%.2f" % REWARD_MIN)
        mm = torch.load(os.path.join(outdir, "adapter_merged.pt"),
                        map_location="cpu", weights_only=False)
        rnet = Net(meta)
        rnet.load_state_dict(mm)
        r1 = acc_at(rnet, X_te, y_te)
        r2 = acc_at(rnet, X_te, y_te)
        if abs(r1 - r2) < 1e-12:
            ok.append("deterministic re-eval stable (%.6f==%.6f)" % (r1, r2))
        else:
            ok.append("FAIL nondeterministic re-eval")
    else:
        ok.append("FAIL missing eval_metrics.json")

    failing = [s for s in ok if s.startswith("FAIL")]
    print(" ; ".join(ok))
    print("RESULT: %s" % ("PASS" if not failing else "FAIL " + "; ".join(failing)))
    return 0 if not failing else 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: verify.py <casedir> <outdir>")
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))