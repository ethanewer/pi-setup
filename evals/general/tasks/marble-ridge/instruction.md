# Marble Ridge: an optionally gated LayerNorm as a lean Triton kernel

Your on-device inference stack needs one more fused op shipped in pure
Triton: **LayerNorm over the last dimension with an optional learned gate**,
matched float-for-float against a local PyTorch reference. There is no GPU in
this container, so the kernel must run through Triton's CPU interpreter.

Your single deliverable is:

- `/app/gated_norm.py` — the Triton kernel(s) plus the public Python entry
  point `gated_layernorm`.

## Environment

- Triton runs in **CPU interpreter mode**: set the env var
  `TRITON_INTERPRET=1` **before** importing triton, then a `@triton.jit`
  kernel executes on the CPU. Confirm with `triton.__version__` (expect
  `3.4.0`).
- `torch` (CPU build), `numpy`, and `triton==3.4.0` are installed.

## The operation (exact contract)

Expose this function in `/app/gated_norm.py`:

```python
def gated_layernorm(x, weight, bias, gate=None, eps=1e-5) -> torch.Tensor
```

Inputs (all `torch.float32`, contiguous, CPU):

- `x`: shape `(B, S, D)` — the activations to normalize over the last
  dimension. `B`, `S`, `D` are arbitrary positive integers; none of them is
  guaranteed to be a power of two, and any of them may be `1`.
- `weight`, `bias`: shape `(D,)` — the per-feature scale and shift.
- `gate`: **optional**, shape `(D,)` or `None` — a learned per-feature gate.
- `eps`: small float (default `1e-5`).

Math. For every row `r` of the flattened `(B*S, D)` view and every feature
`d`, with `mean_r` and `var_r` taken over the `D` features of row `r`
(**population** variance, i.e. divide by `D`, not `D-1`):

```
mean_r = (1/D) * sum_d x[r,d]
var_r  = (1/D) * sum_d (x[r,d] - mean_r)^2
norm   = (x[r,d] - mean_r) / sqrt(var_r + eps)
out[r,d] = norm * weight[d] + bias[d]              # no-gate mode
out[r,d] = sigmoid(gate[d]) * (norm * weight[d] + bias[d])   # gate mode
```

The gate branch is selected by whether `gate is None` — both modes must work
in the same entry point. The returned tensor must have the same shape as `x`
and dtype `torch.float32`, and must be a fresh tensor (not an in-place edit
of an input).

## Kernel rules (enforced by inspection and execution)

1. Kernel bodies (every `@triton.jit` function in the file) must be written
   **exclusively with `triton.language` ops**. No `torch.*` calls, no
   `numpy`/`np.*` calls, no `math.*` calls inside kernel bodies — the
   grader inspects the kernel AST and fails the task on any violation.
2. **No sum helper.** `tl.sum`, `triton.language.sum`, `.sum(...)` method
   calls, and the Python built-in `sum(...)` are forbidden — the first three
   anywhere in the file, the built-in inside kernel bodies. Write your
   reductions out explicitly with other `tl` ops.
3. Handle non-power-of-two `D` yourself (padding/masking is your problem),
   and do not assume anything about `B` or `S` beyond `>= 1`.

## How it will be graded

The grader imports `/app/gated_norm.py` under `TRITON_INTERPRET=1` and runs
`gated_layernorm` on a battery of shapes and both gate modes — including
shapes you should assume are hidden: single-row shapes (`B=1` and/or
`S=1`), `D=1`, and odd values of `D` such as `7`, `17`, `33`, `100`. Each
result is compared against a pure-torch reference computed with the formula
above, using `rtol=1e-4, atol=1e-6`; the dtype must be `float32`. The source
is then inspected for the kernel rules above.

## Constraints

- Standard library + `torch` + `triton` only; no network access.
- Keep everything in the single deliverable `/app/gated_norm.py`.
