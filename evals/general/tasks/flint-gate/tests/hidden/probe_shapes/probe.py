#!/usr/bin/env python3
"""flint-gate hidden battery: execute gated_layernorm on edge shapes in both
gate modes and compare against a pure-torch reference (rtol=1e-4, atol=1e-6).

Shapes include B=1, S=1, D=1, and odd non-power-of-two feature dims; gate is
exercised both as a (D,) tensor and as None; eps is passed explicitly on some
cases so a hard-coded eps cannot pass.
"""
import os

os.environ["TRITON_INTERPRET"] = "1"

import sys

sys.path.insert(0, "/app")

import torch

CASES = [
    # (B, S, D), use_gate, eps
    ((2, 4, 64), True, 1e-5),
    ((2, 4, 64), False, 1e-5),
    ((1, 1, 8), False, 1e-5),
    ((1, 1, 8), True, 1e-5),
    ((1, 5, 7), True, 1e-5),          # odd D
    ((1, 5, 7), False, 1e-6),
    ((3, 2, 33), True, 1e-5),         # odd D
    ((3, 2, 33), False, 1e-5),
    ((4, 1, 17), True, 1e-6),         # S=1, odd D, custom eps
    ((2, 2, 1), True, 1e-5),          # D=1 degenerate variance
    ((2, 2, 1), False, 1e-5),
    ((1, 3, 100), False, 1e-5),       # B=1, non-pow2
    ((5, 1, 12), True, 1e-5),
    ((1, 1, 3), False, 1e-5),         # smallest odd D > 1
]


def reference(x, w, b, g, eps):
    m = x.mean(-1, keepdim=True)
    v = x.var(-1, unbiased=False, keepdim=True)
    y = (x - m) / torch.sqrt(v + eps) * w + b
    if g is not None:
        y = torch.sigmoid(g) * y
    return y


def main() -> int:
    try:
        import gated_norm
    except Exception as exc:
        print("probe: cannot import /app/gated_norm.py: %s" % exc)
        return 1

    fn = getattr(gated_norm, "gated_layernorm", None)
    if not callable(fn):
        print("probe: gated_layernorm entry point missing")
        return 1

    failures = 0
    for i, (shape, use_gate, eps) in enumerate(CASES):
        torch.manual_seed(1000 + i)
        D = shape[-1]
        x = torch.randn(*shape, dtype=torch.float32) * 1.4
        w = (0.6 + torch.rand(D, dtype=torch.float32))
        b = torch.randn(D, dtype=torch.float32) * 0.2
        g = torch.randn(D, dtype=torch.float32) if use_gate else None

        try:
            out = fn(x, w, b, g, eps=eps) if use_gate else fn(x, w, b, None, eps=eps)
        except TypeError:
            # tolerate (x, weight, bias, gate, eps) positional style
            try:
                out = fn(x, w, b, g, eps)
            except Exception as exc:
                print("probe: case %s gate=%s raised: %s"
                      % (shape, use_gate, exc))
                failures += 1
                continue
        except Exception as exc:
            print("probe: case %s gate=%s raised: %s" % (shape, use_gate, exc))
            failures += 1
            continue

        if out.dtype != torch.float32:
            print("probe: case %s returned dtype %s" % (shape, out.dtype))
            failures += 1
            continue
        if tuple(out.shape) != tuple(shape):
            print("probe: case %s returned shape %s" % (shape, tuple(out.shape)))
            failures += 1
            continue
        if out.data_ptr() == x.data_ptr():
            print("probe: case %s edited x in place" % (shape,))
            failures += 1
            continue

        expected = reference(x, w, b, g, eps)
        if not torch.allclose(out, expected, rtol=1e-4, atol=1e-6):
            diff = (out - expected).abs().max().item()
            print("probe: case %s gate=%s diverges (max abs diff %.3e)"
                  % (shape, use_gate, diff))
            failures += 1
            continue
        print("probe: case %s gate=%s eps=%g ok" % (shape, use_gate, eps))

    if failures:
        print("probe: %d case(s) failed" % failures)
        return 1
    print("probe: all %d hidden cases passed" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
