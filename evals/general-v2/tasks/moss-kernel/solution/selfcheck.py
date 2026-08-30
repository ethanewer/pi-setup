#!/usr/bin/env python3
"""Self-check for the MOSS Triton kernel: varied shapes vs a torch reference."""
import gzip
import os
import sys

os.environ["TRITON_INTERPRET"] = "1"

import torch

import importlib.util

spec = importlib.util.spec_from_file_location("gated_ops", "/app/gated_ops.py")
gated_ops = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gated_ops)


def reference(a, b, g, w, eps):
    gate = torch.tanh(g).unsqueeze(1)
    h = gate * a + (1.0 - gate) * b + 1.0
    msq = h.pow(2).mean(dim=1, keepdim=True)
    scale = torch.rsqrt(msq + eps)
    return h * w.unsqueeze(0) * scale


def main():
    shapes = [(1, 1), (3, 7), (5, 100), (2, 777), (4, 1024)]
    ok = True
    for i, (n, d) in enumerate(shapes):
        torch.manual_seed(1000 + i)
        a = torch.randn(n, d, dtype=torch.float32)
        b = torch.randn(n, d, dtype=torch.float32)
        g = torch.randn(n, dtype=torch.float32)
        w = torch.randn(d, dtype=torch.float32)
        eps = [1e-6, 1e-6, 1e-5, 1e-4, 1e-6][i]
        out = gated_ops.gated_shift_rms(a, b, g, w, eps=eps)
        want = reference(a, b, g, w, eps)
        if out.shape != (n, d) or out.dtype != torch.float32 or not out.is_contiguous():
            print("FAIL shape/dtype/contiguity for (%d,%d)" % (n, d))
            ok = False
            continue
        if not torch.allclose(out, want, atol=1e-4, rtol=1e-4):
            dev = (out - want).abs().max().item()
            print("FAIL numerics for (%d,%d), max abs diff %.3e" % (n, d, dev))
            ok = False
        again = gated_ops.gated_shift_rms(a, b, g, w, eps=eps)
        if not torch.equal(again, out):
            print("FAIL determinism for (%d,%d)" % (n, d))
            ok = False
    print("SELFCHECK PASS" if ok else "SELFCHECK FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
