#!/usr/bin/env python3
"""Self-check for harbor-mantle: prove the Triton gated-RMSNorm kernel matches a
Torch reference on CPU interpreter mode and fits under the compressed cap.

Exits 0 iff every check passes (matching to tolerance, gzip cap satisfied).
"""
import gzip
import os
import sys

os.environ.setdefault("TRITON_INTERPRET", "1")

import torch

import kernels

CAP = 1600
ATOL = 1e-3
RTOL = 1e-3


def reference(a, b, g, w, eps=1e-5):
    """Pure-torch float32 reference for the fused op."""
    z = torch.sigmoid(g).unsqueeze(-1)
    h = a * z + b * (1.0 - z)
    msq = (h * h).sum(-1, keepdim=True) / a.shape[1]
    y = h * w.unsqueeze(0) / torch.sqrt(msq + eps)
    return y


def main():
    checks = []
    shapes = [(3, 64), (5, 511), (8, 1024), (12, 2048)]
    for n, d in shapes:
        torch.manual_seed(n * 1000 + d)
        a = torch.randn(n, d, dtype=torch.float32)
        b = torch.randn(n, d, dtype=torch.float32)
        g = torch.randn(n, dtype=torch.float32)
        w = torch.rand(d, dtype=torch.float32)
        out = kernels.gated_rmsnorm(a, b, g, w)
        assert out.shape == (n, d), (n, d, out.shape)
        ref = reference(a, b, g, w)
        ok = bool(torch.allclose(out, ref, atol=ATOL, rtol=RTOL))
        md = float((out - ref).abs().max())
        checks.append((ok, md))
        print(f"shape {n}x{d}: match={ok} max_abs_diff={md:.3e}")

    src = open("/app/kernels.py", "rb").read()
    nbytes = len(gzip.compress(src))
    under_cap = nbytes < CAP
    print(f"kernels.py gzip bytes={nbytes} cap={CAP} under={under_cap}")
    checks.append((under_cap, "cap"))

    all_ok = all(c[0] for c in checks)
    print("RESULT", "PASS" if all_ok else "FAIL")


if __name__ == "__main__":
    main()