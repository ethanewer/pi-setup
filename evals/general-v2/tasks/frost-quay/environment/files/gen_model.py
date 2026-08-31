#!/usr/bin/env python3
"""Build-time generator for the visible tiny encoder checkpoint (frost-quay).

Runs once during image build with the pinned toolchain, then is deleted so the
live container only carries the resulting HF-format model directory.
"""
import torch
from transformers import BertConfig, BertModel

CONFIG = BertConfig(
    vocab_size=64,
    hidden_size=16,
    num_hidden_layers=1,
    num_attention_heads=2,
    intermediate_size=24,
)

torch.manual_seed(4242)
model = BertModel(CONFIG)
model.eval()
model.save_pretrained("/app/model_repo")
print("gen_model: wrote /app/model_repo",
      "hidden_size=%d" % CONFIG.hidden_size,
      "params=%d" % sum(p.numel() for p in model.parameters()))
