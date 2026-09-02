#!/usr/bin/env python3
"""prism-hearth: build-time asset builder (fully offline, fixed seeds).

* /app/models/verlok_lm/     local causal LM (GPT2 config) checkpoint
* /app/tokenizers/verlok_bpe/ local BPE tokenizer saveable/loadable via AutoTokenizer
* /app/weights/hearth_net.pt  HearthNet game-evaluation state dict
* /app/folds/*.npy            bag features for the visible job
* /app/job.json               the visible benchmark scenario
"""
import os
import json
import numpy as np
import torch

SEED = 20260717
rng = np.random.RandomState(SEED)

import torch
from transformers import GPT2Config, GPT2LMHeadModel, PreTrainedTokenizerFast
from tokenizers import ByteLevelBPETokenizer

# ------------------------------------------------------------------------- BPE
seed_ll = [
    "prism shard glint over the hearth ridge",
    "verge widens the war amber lantern hoping to guard",
    "the amber osm shortens knowing the horizon is faint",
    "cautious line of footbridges taps the scoring ring",
    "the garrison braid ahead of the glass titan",
    "deliberate pegs gavel the meridian at dawn",
    "spare the folded hearth while the grid reloads",
    "the crooked third party turns to the bounded west",
]
corpus_lines = []
for i in range(180):
    for ln in seed_ll:
        corpus_lines.append(f"{i}: {ln} :: {ln[::-1]}")
for _ in range(600):
    a = rng.randint(0, len(seed_ll))
    b = rng.randint(0, len(seed_ll))
    corpus_lines.append(f"fold {a} {b} {seed_ll[a]} {seed_ll[b]}")
corpus_sentences = corpus_lines

tok_inner = ByteLevelBPETokenizer()
tok_inner.train_from_iterator(
    corpus_sentences,
    vocab_size=760,
    min_frequency=1,
    special_tokens=["<pad>", "<unk>", "<s>", "</s>"],
)

tok = PreTrainedTokenizerFast(tokenizer_object=tok_inner)
tok.add_special_tokens(
    {"unk_token": "<unk>", "bos_token": "<s>", "eos_token": "</s>", "pad_token": "<pad>"}
)
tok.pad_side = "right"
print("final vocab size =", tok.vocab_size)

tok_dir = "/app/tokenizers/verlok_bpe"
os.makedirs(tok_dir, exist_ok=True)
tok.save_pretrained(tok_dir)
vocab_size = tok.vocab_size

# ----------------------------------------------------------------- causal LM
torch.manual_seed(90210)
cfg = GPT2Config(
    vocab_size=vocab_size,
    n_positions=768,
    n_embd=96,
    n_layer=2,
    n_head=4,
    n_inner=384,
    activation_function="gelu_new",
    pad_token_id=tok.pad_token_id,
    bos_token_id=tok.bos_token_id,
    eos_token_id=tok.eos_token_id,
)
lm = GPT2LMHeadModel(cfg)
lm_dir = "/app/models/verlok_lm"
os.makedirs(lm_dir, exist_ok=True)
lm.save_pretrained(lm_dir)
print("saved causal LM vocab", vocab_size)

# ----------------------------------------------------------------- HearthNet
torch.manual_seed(555_123)
W1 = torch.randn(10, 784) * 0.12
b1 = torch.randn(10) * 0.10
W2 = torch.randn(10, 10) * 0.20
b2 = torch.randn(10) * 0.10
Gw = torch.randn(10) * 0.30
Gb = torch.randn(1) * 0.15 + 0.7
Oc = torch.randn(3, 10) * 0.20
Ob = torch.randn(3) * 0.10
sd = {
    "enc.weight": W1, "enc.bias": b1,
    "act.weight": W2, "act.bias": b2,
    "gate.w": Gw, "gate.b": Gb,
    "outc.weight": Oc, "outc.bias": Ob,
}
os.makedirs("/app/weights", exist_ok=True)
torch.save(sd, "/app/weights/hearth_net.pt")
print("HearthNet W1", tuple(W1.shape), "W2", tuple(W2.shape))

# ----------------------------------------------------------------- visible job
np_rng = np.random.RandomState(777_001)
os.makedirs("/app/folds", exist_ok=True)
n_reqs = 9
reqs, sizes = [], []
for i in range(n_reqs):
    bag_n = int(np_rng.randint(2, 8))
    sizes.append(bag_n)
    np.save("/app/folds/fold%02d.npy" % i, np_rng.normal(0.5, 1.0, (bag_n, 784)).astype(np.float32))
    reqs.append({"id": i, "feat": "/app/folds/fold%02d.npy" % i,
                 "target": int(np_rng.randint(0, 10)), "span": 1})

prompt = tok.encode("prism shard glint over the hearth ridge")[:40]
job = {
    "name": "verge-equilibrated-default",
    "batch_budget": 4,
    "window": 4,
    "prompt_tokens": prompt,
    "requests": reqs,
}
with open("/app/job.json", "w") as f:
    json.dump(job, f, indent=1)
print("visible job requests", n_reqs, "bag sizes", sizes, "prompt_len", len(prompt))
print("BUILD_ASSETS_OK")