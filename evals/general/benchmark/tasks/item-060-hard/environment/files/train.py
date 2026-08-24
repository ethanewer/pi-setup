"""Fine-tuning pipeline for MiniTransformer (hard variant).

Since the network is deeper (3 blocks), the requested freeze is more precise:
ONLY the parameters of the LAST transformer block plus the classification head
are trainable; everything before them — embeddings, positional parameter,
earlier blocks, layer norms, the final norm — must be frozen exactly.

Implement `infer_config` and `freeze_policy`; the training loop, evaluation,
checkpointing and reporting are already written.
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
    succeeds with strict=True. Compute it from the state dict alone:
      d_model    = state["token_emb.weight"].shape[1]
      vocab      = state["token_emb.weight"].shape[0]
      max_len    = state["pos_emb"].shape[1]
      n_heads    = state["blocks.0.attn.head_scale"].shape[0]
      n_layers   = number of distinct block indices in the keys
      num_classes= state["head.weight"].shape[0]
    Raise if load would not be exact; use load_state_dict(strict=True) to
    confirm (use the block index set to pin n_layers).
    """
    raise NotImplementedError("infer the config from the state dict")


def freeze_policy(model, allowed_prefixes):
    """Leave requires_grad=True ONLY on parameters whose names start with one
    of allowed_prefixes (here: the strings in the passed list); set
    requires_grad=False on every other parameter. Return
    (trainable_param_count, frozen_param_count) counted in elements.
    """
    raise NotImplementedError("freeze exactly the allowed parameters")


def train(model, seqs, tgt, steps=400, lr=5e-3, batch=32):
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
    model.load_state_dict(state, strict=True)

    # Requested freeze: exactly the LAST block (blocks.2.) plus the head.
    last_block = f"blocks.{cfg.n_layers - 1}."
    trainable, frozen = freeze_policy(model, [last_block, "head."])

    tr_seqs, tr_tgt = make_dataset(seed=11, n=200, cfg=cfg)
    va_seqs, va_tgt = make_dataset(seed=22, n=64, cfg=cfg)
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
        "trainable_prefixes": [last_block, "head."],
        "trainable_params": trainable,
        "frozen_params": frozen,
        "val_accuracy": val_acc,
        "steps": 400,
    }
    json.dump(report, open(f"{OUT_DIR}/report.json", "w"), indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()