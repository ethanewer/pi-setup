# Harbor-Mantle: a gated RMSNorm as a lean Triton kernel

You maintain a small on-device kernels suite. A new op must be shipped: a
**gated weighted combination followed by RMS-normalization**, implemented as a
single **Triton kernel** written with only `triton.language` ops, matched
float-for-float against a local PyTorch reference. The submitted source must
also stay under a hard compressed byte ceiling.

Your job is to author two deliverables under `/app`:

- `/app/kernels.py` — the Triton kernel plus its public Python entry point.
- `/app/check.py` — a self-check script that proves the kernel is correct and
  within budget.

## Environment

- This container has **no GPU**. Triton is run in **CPU interpreter mode**: set
  the env var `TRITON_INTERPRET=1` **before** importing triton, then a
  `@triton.jit` kernel executes on the CPU. Confirm with `triton.__version__`
  (expect `3.4.0`).
- `torch` (CPU build), `numpy`, and `triton==3.4.0` are installed.

## The operation (exact contract)

Inputs:

- `a`, `b`: row-parallel input tensors, shape `(N, D)`, `dtype=torch.float32`,
  contiguous, on CPU.
- `g`: gate vector, shape `(N,)`, `dtype=torch.float32`.
- `w`: RMS weight vector, shape `(d,)`, `dtype=torch.float32`.
- `eps`: small scalar (default `1e-5`).

For every row `n` and column `d`:

```
gate_n = sigmoid(g[n])
h[n,d] = gate_n * a[n,d] + (1 - gate_n) * b[n,d]
msq_n  = (1/d) * sum_j h[n,j]^2         # mean square over the row's columns
rms_n  = rsqrt(msq_n + eps)
out[n,d] = h[n,d] * w[d] * rms_n
```

So each row is gated between its two parallel inputs, then everything on the
row is scaled to unit-RMS (mean-square normalization) and weighted by `w`.
`sigmoid` and `rsqrt` must be computed as scalar math inside the kernel using
Triton ops (e.g. `tl.sigmoid` / `1/sqrt` via `tl.sqrt`).

## `/app/kernels.py`

Expose, with exact name and signature:

```python
def gated_rmsnorm(a, b, g, w, eps=1e-5, BLOCK=2048) -> torch.Tensor
```

- Returns a new contiguous `torch.Tensor` of shape `(N, d)`, `dtype=float32`.
- The heavy lifting must live in one `@triton.jit` kernel that:
  - reads inputs with masked loads and writes the result with masked stores,
  - computes the per-row mean-square reduction **inside the kernel** using
    `triton.language` ops (a `tl.sum` over the block is fine),
  - uses **only** `triton.language` ops — no calling into torch from within
    the `@triton.jit` body.
- Launch with one program per row. Choose the kernel's block size so that one
  row fits in one program. The grader calls `gated_rmsnorm(a, b, g, w)` without
  a block argument, so your default `BLOCK` must be a power of two that covers
  `d <= 2048`; mask the trailing lanes when `d` is not a power of two.

## `/app/check.py`

A self-contained, runnable script (exit code 0 on success) that:

1. Sets `TRITON_INTERPRET=1` (idempotent) and imports `/app/kernels.py`.
2. Generates several float32 inputs of **varied** shapes (small textures, a
   non-power-of-two `d`, a large `d`), runs `gated_rmsnorm`, and asserts each
   result matches the same op computed in plain PyTorch to
   `atol=1e-3, rtol=1e-3` (elementwise `torch.allclose` with those tolerances).
3. Verifies the implementation is under the cap: `len(gzip.compress(open
   "/app/kernels.py","rb").read()) < 1600`.
4. Prints a short PASS/FAIL line and exits `0` iff everything passed.

## Compatibility rules (the hidden checks will probe these)

- Must generalize to unseen `N` and `d` values (the grader re-runs your kernel
  and its own independent torch reference on fresh shapes). Never special-case
  a fixed N or d, and never precompute answers.
- Handle non-power-of-two `d` correctly by masking, not by truncating.
- `g` is always length `N`; `w` length `d`; `a` and `b` share shape `(N, d)`.
- Output dtype and shape must be exactly `(N, d)` float32.
- Keep `/app/kernels.py` **lean**: the compressed cap is `1600` gzip bytes —
  hard. Do not pad it with prose; prefer a single fused kernel.
- Do not read, modify, or reference anything under `/tests` if present; it is
  not part of your task.

The grader runs `/app/check.py` itself and re-invokes `kernels.gated_rmsnorm`
on hidden shapes against its own reference, then enforces the byte cap. When
you are done, `python3 -u /app/check.py` must exit `0`.