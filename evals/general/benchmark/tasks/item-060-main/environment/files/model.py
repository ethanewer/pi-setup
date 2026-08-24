"""A small configurable Transformer with a classification head.

The exact hyperparameters are NOT hardcoded here: they are hidden inside the
serialized state dict at /app/models/base_state.pt. The whole point of the task
is to re-derive them from the tensor shapes in that dict.
"""
import math
from dataclasses import dataclass

import torch
import torch.nn as nn
import torch.nn.functional as F


@dataclass
class TConfig:
    vocab_size: int = 32
    max_len: int = 16
    d_model: int = 8
    n_heads: int = 2
    n_layers: int = 2
    num_classes: int = 3

    def __post_init__(self):
        assert self.d_model % self.n_heads == 0, "d_model must be divisible by n_heads"


class MLP(nn.Module):
    def __init__(self, d_model: int):
        super().__init__()
        self.c_fc = nn.Linear(d_model, 4 * d_model, bias=True)
        self.c_proj = nn.Linear(4 * d_model, d_model, bias=True)

    def forward(self, x):
        return self.c_proj(F.gelu(self.c_fc(x)))


class Attention(nn.Module):
    def __init__(self, cfg: TConfig):
        super().__init__()
        self.n_heads = cfg.n_heads
        self.head_dim = cfg.d_model // cfg.n_heads
        self.q = nn.Linear(cfg.d_model, cfg.d_model, bias=True)
        self.k = nn.Linear(cfg.d_model, cfg.d_model, bias=True)
        self.v = nn.Linear(cfg.d_model, cfg.d_model, bias=True)
        self.o = nn.Linear(cfg.d_model, cfg.d_model, bias=True)
        # One scalar per head: its length in the state dict reveals n_heads.
        self.head_scale = nn.Parameter(torch.ones(cfg.n_heads))

    def forward(self, x):
        B, T, C = x.shape
        q = self.q(x).view(B, T, self.n_heads, self.head_dim).transpose(1, 2)
        k = self.k(x).view(B, T, self.n_heads, self.head_dim).transpose(1, 2)
        v = self.v(x).view(B, T, self.n_heads, self.head_dim).transpose(1, 2)
        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        att = att * self.head_scale.view(1, self.n_heads, 1, 1)
        att = F.softmax(att, dim=-1)
        y = (att @ v).transpose(1, 2).contiguous().view(B, T, C)
        return self.o(y)


class Block(nn.Module):
    def __init__(self, cfg: TConfig):
        super().__init__()
        self.ln1 = nn.LayerNorm(cfg.d_model)
        self.attn = Attention(cfg)
        self.ln2 = nn.LayerNorm(cfg.d_model)
        self.mlp = MLP(cfg.d_model)

    def forward(self, x):
        x = x + self.attn(self.ln1(x))
        x = x + self.mlp(self.ln2(x))
        return x


class MiniTransformer(nn.Module):
    """Embedding + positional embedding + `n_layers` transformer blocks +
    final LayerNorm + mean-pooling + linear classification head."""

    def __init__(self, cfg: TConfig):
        super().__init__()
        self.cfg = cfg
        self.token_emb = nn.Embedding(cfg.vocab_size, cfg.d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, cfg.max_len, cfg.d_model))
        self.blocks = nn.ModuleList([Block(cfg) for _ in range(cfg.n_layers)])
        self.final_norm = nn.LayerNorm(cfg.d_model)
        self.head = nn.Linear(cfg.d_model, cfg.num_classes, bias=True)

    def forward(self, idx):
        B, T = idx.shape
        x = self.token_emb(idx) + self.pos_emb[:, :T]
        for blk in self.blocks:
            x = blk(x)
        x = self.final_norm(x)
        pooled = x.mean(dim=1)
        return self.head(pooled)


def build_model(cfg: TConfig) -> MiniTransformer:
    return MiniTransformer(cfg)