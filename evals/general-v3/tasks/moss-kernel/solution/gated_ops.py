"""Shifted gated blend + RMS rescale as a single Triton kernel (MOSS op).

Math, per row n / column d:
    gate_n = tanh(g[n])  (== 2*sigmoid(2*g[n]) - 1)
    h      = gate_n*a + (1-gate_n)*b + 1.0
    out    = h * w * rsqrt( mean_j(h^2 over the D real columns) + eps )
"""
import os

os.environ.setdefault("TRITON_INTERPRET", "1")

import torch
import triton
import triton.language as tl

EPS = 1e-6


@triton.jit
def gated_shift_rms_kernel(A, B, G, W, OUT, D, eps, BLOCK: tl.constexpr):
    pid = tl.program_id(0)
    offs = pid * D + tl.arange(0, BLOCK)
    mask = tl.arange(0, BLOCK) < D
    a = tl.load(A + offs, mask=mask, other=0.0)
    b = tl.load(B + offs, mask=mask, other=0.0)
    g = tl.load(G + pid)
    gate = 2.0 * tl.sigmoid(2.0 * g) - 1.0
    h = gate * a + (1.0 - gate) * b + 1.0
    h = tl.where(mask, h, 0.0)  # padded lanes must not pollute the mean square
    msq = tl.sum(h * h) / D
    scale = 1.0 / tl.sqrt(msq + eps)
    w = tl.load(W + tl.arange(0, BLOCK), mask=mask, other=0.0)
    tl.store(OUT + offs, h * w * scale, mask=mask)


def gated_shift_rms(a, b, g, w, eps=EPS, BLOCK=1024):
    if a.shape != b.shape:
        raise ValueError("a and b must share shape (N, D)")
    if a.dim() != 2:
        raise ValueError("a must be 2-D (N, D)")
    n, d = a.shape
    if g.numel() != n:
        raise ValueError("g must have length N")
    if w.numel() != d:
        raise ValueError("w must have length D")
    if d > BLOCK:
        raise ValueError("D=%d exceeds BLOCK=%d" % (d, BLOCK))
    out = torch.empty_like(a)
    gated_shift_rms_kernel[(n,)](a, b, g, w, out, d, eps, BLOCK=BLOCK)
    return out
