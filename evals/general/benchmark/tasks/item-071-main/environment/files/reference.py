"""Canonical single-process reference for the pipeline-parallel task (item-071).

This tiny LLaMA-style stack defines the *reference* semantics every parallel
shard layout must reproduce: same forward, same loss, same gradients, same
SGD updates. It is deterministic (fixed seed, float32, single-threaded).

Model contract (do not change these constants anywhere):

- vocab 64, d_model 32, n_heads 8, head_dim 4  -> attention output width 32
- 6 decoder blocks; each block = RMSNorm + multi-head self-attention
  (qkv projection, softmax attention, output projection) + RMSNorm + MLP
  (gate/up projections with SiLU to hidden 64, down projection back to 32)
- final RMSNorm + tied-style head projection to vocab
"""

import math

import torch
import torch.nn.functional as F

VOCAB = 64
DMODEL = 32
N_HEADS = 8
HEAD_DIM = 4
N_LAYERS = 6
HIDDEN = 2 * DMODEL  # 64


def build_params(seed=20260407):
    """Deterministic canonical parameter dict, float32, CPU."""
    torch.manual_seed(seed)
    p = {}
    p["embed"] = torch.empty(VOCAB, DMODEL).normal_(0.0, 0.3)
    for i in range(N_LAYERS):
        p[f"blocks.{i}.attn.qkv"] = torch.empty(3 * N_HEADS * HEAD_DIM, DMODEL).normal_(0.0, 0.08)
        p[f"blocks.{i}.attn.out"] = torch.empty(DMODEL, N_HEADS * HEAD_DIM).normal_(0.0, 0.08)
        p[f"blocks.{i}.attn.ln"] = torch.ones(DMODEL)
        p[f"blocks.{i}.ffn.gate"] = torch.empty(HIDDEN, DMODEL).normal_(0.0, 0.08)
        p[f"blocks.{i}.ffn.up"] = torch.empty(HIDDEN, DMODEL).normal_(0.0, 0.08)
        p[f"blocks.{i}.ffn.down"] = torch.empty(DMODEL, HIDDEN).normal_(0.0, 0.08)
        p[f"blocks.{i}.ffn.ln2"] = torch.ones(DMODEL)
    p["head.ln"] = torch.ones(DMODEL)
    p["head.out"] = torch.empty(VOCAB, DMODEL).normal_(0.0, 0.3)
    return p


def rms(y, g):
    # (y: [B,S,D]) elementwise RMSNorm with gain g
    s = y.pow(2).mean(-1, keepdim=True) + 1e-5
    return (y / s.sqrt()) * g


def block_forward(p, prefix, h):
    # h: [B,S,D]
    h1 = rms(h, p[f"{prefix}.attn.ln"])
    qkv = h1 @ p[f"{prefix}.attn.qkv"].T  # [B,S,3*32]
    q, k, v = qkv.chunk(3, dim=-1)
    B, S, _ = q.shape
    q = q.view(B, S, N_HEADS, HEAD_DIM).transpose(1, 2)
    k = k.view(B, S, N_HEADS, HEAD_DIM).transpose(1, 2)
    v = v.view(B, S, N_HEADS, HEAD_DIM).transpose(1, 2)
    att = torch.softmax((q @ k.transpose(-1, -2)) / math.sqrt(HEAD_DIM), dim=-1)
    o = (att @ v).transpose(1, 2).reshape(B, S, N_HEADS * HEAD_DIM)
    o = o @ p[f"{prefix}.attn.out"].t()
    h = h + o

    h2 = rms(h, p[f"{prefix}.ffn.ln2"])
    g = F.silu(h2 @ p[f"{prefix}.ffn.gate"].t())
    u = (h2 @ p[f"{prefix}.ffn.up"].t())
    down = (g * u) @ p[f"{prefix}.ffn.down"].t()
    h = h + down
    return h


def forward(p, tok):
    B, S = tok.shape
    h = p["embed"][tok]  # [B,S,32]
    for i in range(N_LAYERS):
        h = block_forward(p, f"blocks.{i}", h)
    h = rms(h, p["head.ln"])
    logits = h @ p["head.out"].t()  # [B,S,VOCAB]
    return logits


def loss_from_logits(logits, tok):
    lg = logits[:, :-1, :].reshape(-1, VOCAB)
    lb = tok[:, 1:].reshape(-1)
    return F.cross_entropy(lg, lb)


def loss(p, tok):
    return loss_from_logits(forward(p, tok), tok)


def grads(p, tok):
    p2 = {k: v.clone().requires_grad_(True) for k, v in p.items()}
    loss_g = loss(p2, tok)
    loss_g.backward()
    return {k: v.grad.detach() for k, v in p2.items()}, loss_g.item()


def sgd_update(p, g, lr=0.05):
    return {k: v - lr * g[k] for k, v in p.items()}


def full_name_set():
    return set(build_params(1).keys())