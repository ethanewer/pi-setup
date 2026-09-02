#!/bin/bash
#
# flint-gate oracle. Writes /app/gated_norm.py: an optionally gated LayerNorm
# as a single @triton.jit kernel that runs under TRITON_INTERPRET=1. Reductions
# (mean, variance) are written explicitly with tl.reduce + an @triton.jit
# combine fn — no forbidden summation helper, no torch/numpy inside the kernel
# bodies. Then runs a self-check against a pure-torch reference on several
# shapes and both gate modes. Never reads /tests.
set -euo pipefail

cat > /app/gated_norm.py <<'EOF'
"""Optionally gated LayerNorm over the last dim, as a lean Triton kernel.

Runs through Triton's CPU interpreter (TRITON_INTERPRET=1); there is no GPU.
Public entry point: gated_layernorm(x, weight, bias, gate=None, eps=1e-5).

Kernel rules honored here:
  - kernel bodies use only triton.language ops (no torch/numpy/math);
  - reductions are written out explicitly as tl.reduce passes with an
    @triton.jit combine fn; no summation helper of any kind is used;
  - non-power-of-two D handled via masked loads/stores (BLOCK = next_pow2(D)).
"""
import os

os.environ.setdefault("TRITON_INTERPRET", "1")

import torch
import triton
import triton.language as tl


@triton.jit
def _combine_add(a, b):
    # Explicit associative combine used by the reductions below.
    return a + b


@triton.jit
def _gated_layernorm_kernel(X, W, B, G, OUT, D, eps,
                            HAS_GATE: tl.constexpr, BLOCK: tl.constexpr):
    row = tl.program_id(0)
    offs = tl.arange(0, BLOCK)
    mask = offs < D

    x = tl.load(X + row * D + offs, mask=mask, other=0.0)
    x = tl.where(mask, x, 0.0)

    # Reduction pass 1: row mean.
    total = tl.reduce(x, 0, _combine_add)
    mean = total / D

    # Reduction pass 2: population variance over the D real features only
    # (padded lanes zeroed out so they contribute nothing).
    xc = tl.where(mask, x - mean, 0.0)
    sq_total = tl.reduce(xc * xc, 0, _combine_add)
    var = sq_total / D

    rstd = 1.0 / tl.sqrt(var + eps)

    w = tl.load(W + offs, mask=mask, other=0.0)
    b = tl.load(B + offs, mask=mask, other=0.0)
    y = xc * rstd * w + b

    if HAS_GATE:
        g = tl.load(G + offs, mask=mask, other=0.0)
        y = y * tl.sigmoid(g)

    tl.store(OUT + row * D + offs, y, mask=mask)


def gated_layernorm(x, weight, bias, gate=None, eps=1e-5):
    """Gated LayerNorm over the last dim; gate=None selects the no-gate mode."""
    if x.dim() != 3:
        raise ValueError("x must be 3-D (B, S, D)")
    if x.dtype != torch.float32:
        raise ValueError("x must be float32")
    B, S, D = x.shape
    if weight.shape != (D,) or bias.shape != (D,):
        raise ValueError("weight/bias must match the feature dim")
    if gate is not None and gate.shape != (D,):
        raise ValueError("gate must match the feature dim")

    x = x.contiguous()
    out = torch.empty_like(x)
    rows = B * S
    block = triton.next_power_of_2(D)
    # A valid pointer is required in both modes; weight stands in when the
    # gate is absent (never read on that branch).
    g_ptr = weight if gate is None else gate.contiguous()
    _gated_layernorm_kernel[(rows,)](
        x, weight.contiguous(), bias.contiguous(), g_ptr, out,
        D, eps,
        HAS_GATE=gate is not None,
        BLOCK=block,
    )
    return out
EOF

# ---- self-check against a pure-torch reference (both modes, edge shapes).
TRITON_INTERPRET=1 python3 - <<'PY'
import torch
import sys
sys.path.insert(0, "/app")
from gated_norm import gated_layernorm

def ref(x, w, b, g=None, eps=1e-5):
    m = x.mean(-1, keepdim=True)
    v = x.var(-1, unbiased=False, keepdim=True)
    y = (x - m) / torch.sqrt(v + eps) * w + b
    if g is not None:
        y = torch.sigmoid(g) * y
    return y

torch.manual_seed(7)
for shape in ((2, 4, 64), (1, 1, 8), (1, 5, 7), (3, 2, 33), (2, 2, 1)):
    for use_gate in (False, True):
        x = torch.randn(*shape) * 1.3
        w = 0.6 + torch.rand(shape[-1])
        b = torch.randn(shape[-1]) * 0.2
        g = torch.randn(shape[-1]) if use_gate else None
        out = gated_layernorm(x, w, b, g)
        assert out.dtype == torch.float32
        assert out.shape == x.shape
        assert torch.allclose(out, ref(x, w, b, g), rtol=1e-4, atol=1e-6), shape
print("flint-gate oracle self-check passed")
PY

echo "flint-gate oracle complete -> /app/gated_norm.py"
