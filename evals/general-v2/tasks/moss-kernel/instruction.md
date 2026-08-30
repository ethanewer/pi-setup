# moss-kernel — a shifted gated blend with RMS rescaling as a Triton kernel

Your on-device ops library needs one more fused op shipped: **MOSS** — a
*masked-output gated shift* blend followed by per-row RMS rescaling — written
as a single `@triton.jit` kernel that reproduces a local PyTorch reference in
float32.

## Environment

- This container has **no GPU**. Triton runs in **CPU interpreter mode**: set
  the env var `TRITON_INTERPRET=1` **before** importing triton, then a
  `@triton.jit` kernel executes on the CPU. `torch` (CPU build), `numpy` and
  `triton==3.5.0` are installed.

## The operation (exact contract)

Inputs (all `torch.float32`, contiguous, CPU):

- `a`, `b`: shape `(N, D)`;
- `g`: gate vector, shape `(N,)`;
- `w`: RMS weight vector, shape `(D,)`;
- `eps`: small scalar (default `1e-6`).

For every row `n` and column `d`:

```
gate_n  = tanh(g[n])                       # equivalently 2*sigmoid(2*g[n]) - 1
h[n,d]  = gate_n * a[n,d] + (1 - gate_n) * b[n,d] + 1.0     # the "+1.0 shift"
msq_n   = (1/D) * sum_j h[n,j]^2           # mean square over the D real columns
scale_n = rsqrt(msq_n + eps)
out[n,d] = h[n,d] * w[d] * scale_n
```

Note the two subtleties the hidden checks probe:

- The mean square is over **exactly the D real columns** of the row. If your
  kernel processes the row in a padded block, the padded lanes (which become
  `1.0` after the shift) must be **excluded** from the reduction, or every
  output diverges from the reference.
- `gate` is a scalar per row; the blend and the shift are elementwise.

## Deliverables

1. `/app/gated_ops.py` — exposing exactly:
   ```python
   def gated_shift_rms(a, b, g, w, eps=1e-6, BLOCK=1024) -> torch.Tensor
   ```
   - Returns a **new contiguous** float32 tensor of shape `(N, D)`.
   - The heavy lifting must live in **one `@triton.jit` kernel** that:
     - reads inputs with masked loads and writes with masked stores,
     - computes the per-row mean-square reduction **inside the kernel** using
       only `triton.language` ops (`tl.sum` over the block is fine),
     - computes the gate scalar in-kernel (e.g. `2 * tl.sigmoid(2*g) - 1` or
       a `tanh` formulation — they agree within tolerance),
     - uses **no torch calls inside the kernel body**.
   - One program per row; the default `BLOCK=1024` must cover any `D <= 1024`
     (mask the trailing lanes when `D` is not a power of two). The grader
     calls `gated_shift_rms(a, b, g, w)` with no block argument.
   - Validate shapes (`a`/`b` share `(N, D)`, `g` length `N`, `w` length `D`)
     and raise `ValueError` on mismatch.

2. `/app/selfcheck.py` — a self-contained, runnable script (exit code 0 on
   success) that:
   - sets `TRITON_INTERPRET=1` (idempotently) and imports `/app/gated_ops.py`;
   - exercises **varied** shapes: at least `N=1`, a non-power-of-two `D`
     (e.g. `100`), a large `D = 1024`, and one more of your choosing;
   - asserts each result matches the same op computed in plain PyTorch
     (`torch.allclose` with `atol=1e-4, rtol=1e-4`);
   - prints a short PASS/FAIL line and exits 0 iff everything passed.

## Compatibility rules (the hidden checks probe these)

- Must generalize to unseen `N`, `D`, `eps` values: the grader re-runs your
  kernel on fresh seeded inputs and compares against its own independent
  torch reference (`atol=1e-4, rtol=1e-4`). Never special-case shapes.
- Output dtype/shape must be exactly `(N, D)` float32 and contiguous.
- Two consecutive calls must return byte-identical results (determinism).
- `/app/gated_ops.py` must genuinely use Triton: the source must contain
  `@triton.jit` and import triton.
- Do not read, modify, or reference anything under `/tests` or `/solution`.
- No network access.

## What the grader does

1. Runs `python3 -u /app/selfcheck.py` and requires exit code 0.
2. Re-invokes `gated_ops.gated_shift_rms` on **hidden** `(N, D, seed, eps)`
   cases (including `D=1`, non-power-of-two `D`, and `D=1024`) against its own
   reference, with shape/dtype/contiguity and determinism checks.
3. Verifies the source is a real Triton kernel (`@triton.jit`, no torch calls
   inside the kernel body).
