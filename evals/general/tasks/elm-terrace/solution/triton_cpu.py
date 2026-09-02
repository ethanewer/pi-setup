#!/usr/bin/env python3
"""
Triton CPU (interpreter) deliverable for elm-terrace.

Installs/requires the pinned triton toolchain already provisioned in the image,
then executes a @triton.jit vector kernel in CPU *interpreter* mode
(TRITON_INTERPRET=1) and writes the numeric result to /app/lt_triton_result.json.

The kernel below computes  o = x*g + x*x elementwise — used here as the
low-rank LoRA 'activation-gate' step (LoRA_B = x*(B0+B1*B2*x^2) style) — and we
verify the CPU-interpreted output against a reference pure-torch computation.

Exit 0 iff the interpreted kernel ran and its output matches the reference.
"""
import json
import os

os.environ.setdefault("TRITON_INTERPRET", "1")

import torch
import triton
import triton.language as tl

OUT = os.environ.get("LT_OUT", "/app/lt_triton_result.json")
GATE = 0.5
N = 64


@triton.jit
def gate_kernel(x_ptr, o_ptr, g, n, BLOCK: tl.constexpr):
    pid = tl.program_id(0)
    offs = pid * BLOCK + tl.arange(0, BLOCK)
    m = offs < n
    x = tl.load(x_ptr + offs, mask=m)
    o = x * g + x * x
    tl.store(o_ptr + offs, o, mask=m)


def gate(x, g=GATE):
    out = torch.empty_like(x)
    BLOCK = 256
    grid = (triton.cdiv(x.numel(), BLOCK),)
    gate_kernel[grid](x, out, g, x.numel(), BLOCK=BLOCK)
    return out


def main():
    x = torch.linspace(-1.0, 1.0, N, dtype=torch.float32)
    y = gate(x, GATE)
    expected = x * GATE + x * x
    match = bool(torch.allclose(y, expected, atol=1e-4))
    result = {
        "interpreter": "TRITON_INTERPRET=1",
        "triton_version": triton.__version__,
        "match": match,
        "frob": float(torch.abs(y).sum().item()),
    }
    with open(OUT, "w") as f:
        json.dump(result, f)
    print(json.dumps(result))
    return 0 if match else 1


if __name__ == "__main__":
    raise SystemExit(main())