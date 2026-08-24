"""Fine-tuning pipeline for MiniTransformer.

Two functions are left for you to implement:
  * infer_config(state)   -- read the TConfig out of the state dict shapes
  * freeze_policy(...)    -- freeze exactly the requested parameter subset

Everything else (training loop, evaluation, reporting, checkpointing) is done.
"""
import json

import torch
import torch.nn as nn

from dataset import make_dataset
from model import TConfig, build_model

STATE_PATH = "/app/models/base_state.pt"
OUT_DIR = "/app/output"


def load_state(path):
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(path, map_location="cpu")


def infer_config(state):
    """Infer a TConfig such that build_model(cfg).load_state_dict(state)
    succeeds with strict=True. Compute it from the state dict alone, e.g.:
      d_model      = state["token_emb.weight"].shape[1]
      vocab_size   = state["token_emb.weight"].shape[0]
      max_len      = state["pos_emb"].shape[1]
      n_heads      = state["blocks.0.attn.head_scale"].shape[0]
      n_layers     = number of distinct block indices in the keys
      num_classes  = state["head.weight"].shape[0]
    """
    raise NotImplementedError("infer the config from the state dict")


def freeze_policy(model, allowed_prefixes):
    """Leave requires_grad=True ONLY on parameters whose names start with one
    of allowed_prefixes; set requires_grad=False on every other parameter.
    Return (trainable_param_count, frozen_param_count) counted in elements.
    """
    raise NotImplementedError("freeze exactly the allowed parameters")


def train(model, seqs, tgt, steps=300, lr=5e-3, batch=32):
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    crit = nn.CrossEntropyLoss()
    model.train()
    n = seqs.shape[0]
    for _ in range(steps):
        idx = torch.randperm(n)[:batch]
        loss = crit(model(seqs[idx]), tgt[idx])
        opt.zero_grad()
        loss.backward()
        opt.step()


def evaluate(model, seqs, tgt):
    model.eval()
    with torch.no_grad():
        logits = model(seqs)
        pred = logits.argmax(dim=1)
        return (pred == tgt).float().mean().item()


def main():
    state = load_state(STATE_PATH)
    cfg = infer_config(state)
    model = build_model(cfg)
    model.load_state_dict(state, strict=True)  # must succeed once inference is right

    # Requested freeze: the ONLY trainable parameters are the prediction head.
    trainable, frozen = freeze_policy(model, ["head."])

    tr_seqs, tr_tgt = make_dataset(seed=11, n=160, cfg=cfg)
    va_seqs, va_tgt = make_dataset(seed=22, n=48, cfg=cfg)
    train(model, tr_seqs, tr_tgt)
    val_acc = evaluate(model, va_seqs, va_tgt)

    torch.save(model.state_dict(), f"{OUT_DIR}/finetuned.pt")
    report = {
        "config": {
            "vocab_size": cfg.vocab_size,
            "max_len": cfg.max_len,
            "d_model": cfg.d_model,
            "n_heads": cfg.n_heads,
            "n_layers": cfg.n_layers,
            "num_classes": cfg.num_classes,
        },
        "trainable_params": trainable,
        "frozen_params": frozen,
        "val_accuracy": val_acc,
        "steps": 300,
    }
    json.dump(report, open(f"{OUT_DIR}/report.json", "w"), indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()