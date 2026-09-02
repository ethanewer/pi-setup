"""Gated weighted combination + RMS-norm as a Triton kernel.

Environment has no GPU, so kernels run through Triton's CPU *interpreter*
(TRITON_INTERPRET=1). The public entry point is gated_rmsnorm().

Math, per row n / column d:
    gate_n = sigmoid(g[n])
    h      = gate_n*a + (1-gate_n)*b
    out    = h * w * rsqrt( mean_j(h^2_ij) + eps )
"""
import os

os.environ.setdefault("TRITON_INTERPRET", "1")

import torch
import triton
import triton.language as tl

EPS = 1e-5

@triton.jit
def gated_rmsnorm_kernel(A, B, G, W, OUT, D, eps, BLOCK: tl.constexpr):
    pid = tl.program_id(0)
    offs = pid * D + tl.arange(0, BLOCK)
    mask = tl.arange(0, BLOCK) < D
    a = tl.load(A + offs, mask=mask, other=0.0)
    b = tl.load(B + offs, mask=mask, other=0.0)
    gate = tl.load(G + pid)
    z = tl.sigmoid(gate)
    h = a * z + b * (1.0 - z)
    msq = tl.sum(h * h) / D
    rms = 1.0 / tl.sqrt(msq + eps)
    w = tl.load(W + tl.arange(0, BLOCK), mask=mask, other=0.0)
    out = h * rms * w
    tl.store(OUT + offs, out, mask=mask)


def gated_rmsnorm(a, b, g, w, eps=EPS, BLOCK=2048):
    if not (a.shape == b.shape and b.shape[1] == w.numel() and g.numel() == a.shape[0]):
        raise ValueError("shape mismatch in gated_rmsnorm")
    n, d = a.shape
    out = torch.empty_like(a)
    gated_rmsnorm_kernel[(n,)](a, b, g, w, out, d, eps, BLOCK=BLOCK)
    return out