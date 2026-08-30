#!/usr/bin/env python3
"""Verifier for harbor-mantle. Independent of the oracle: runs the agent's
/app/check.py, then re-runs the Triton kernel on hidden shapes and compares to
a pure-torch reference the verifier computes itself, and enforces the gzip cap.
Exit code 0 iff all checks pass."""
import gzip
import glob
import json
import os
import subprocess
import sys

sys.path.insert(0, "/app")

import torch

CAP = 1600
ATOL = 1e-3
RTOL = 1e-3


def reference(a, b, g, w, eps=1e-5):
    """Pure-torch float32 reference for the fused gated-RMSNorm op."""
    z = torch.sigmoid(g).unsqueeze(-1)
    h = a * z + b * (1.0 - z)
    msq = (h * h).sum(-1, keepdim=True) / a.shape[1]
    return h * w.unsqueeze(0) / torch.sqrt(msq + eps)


def run_hidden(mod, case):
    n, d, seed = case["n"], case["d"], case["seed"]
    torch.manual_seed(seed)
    a = torch.randn(n, d, dtype=torch.float32)
    b = torch.randn(n, d, dtype=torch.float32)
    g = torch.randn(n, dtype=torch.float32)
    w = torch.rand(d, dtype=torch.float32)
    out = mod.gated_rmsnorm(a, b, g, w)
    ref = reference(a, b, g, w)
    good = bool(out.shape == (n, d) and torch.allclose(out, ref, atol=ATOL, rtol=RTOL))
    md = float((out - ref).abs().max()) if out.shape == (n, d) else float("nan")
    return good, md, n, d


def main():
    results = []

    # Deliverable 1: /app/check.py exists, is runnable, and exits 0.
    if not os.path.isfile("/app/check.py"):
        print("FAIL: /app/check.py missing")
        return 1
    r = subprocess.run(["python3", "-u", "/app/check.py"], capture_output=True, text=True)
    ok = (r.returncode == 0)
    results.append(ok)
    print("check.py rc=%d ok=%s" % (r.returncode, ok))

    # Deliverable 2: /app/kernels.py present, is a Triton kernel, and stays
    # under the compressed cap.
    if not os.path.isfile("/app/kernels.py"):
        print("FAIL: /app/kernels.py missing")
        return 1
    src = open("/app/kernels.py").read()
    results.append("@triton.jit" in src)
    results.append("gated_rmsnorm" in src)
    nbytes = len(gzip.compress(open("/app/kernels.py", "rb").read()))
    under = nbytes < CAP
    results.append(under)
    print("gzip(kernels.py)=%d cap=%d under=%s" % (nbytes, CAP, under))

    # Hidden generalization: run the kernel on unseen shapes and compare to the
    # verifier's own torch reference (independent of the oracle).
    hiddens = sorted(glob.glob("/tests/hidden/*.json"))
    if not hiddens:
        print("FAIL: no hidden cases found")
        return 1
    import kernels as kern
    for hp in hiddens:
        with open(hp) as f:
            case = json.load(f)
        good, md, n, d = run_hidden(kern, case)
        results.append(good)
        print("hidden %s %dx%d match=%s max_abs_diff=%.3e"
              % (os.path.basename(hp), n, d, good, md))

    all_ok = all(results)
    print("RESULT", "PASS" if all_ok else "FAIL")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())