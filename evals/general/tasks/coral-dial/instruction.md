# coral-dial — the Marrowwave sharded projection service

Marrowwave serves a small embedding model whose projections are **tensor
parallel**: the output dimension of each linear layer is split across
`world_size` virtual ranks, each rank computes its local output block from a
column-block ("shard") of the full weight, and the blocks are **all-gathered**
(concatenated) to reconstruct the full output. Backward passes must expose the
**exact per-rank slice of the dense weight gradient** so gradient fragments can
be reduced across the wire.

You must write one program, `/app/tp_linear.py`, that implements the sharded
layer and a validation CLI, then run the validation on the shipped config to
produce `/app/validate.json`.

The grader re-runs `/app/tp_linear.py` on **hidden configurations** (different
dimensions, world sizes, seeds, batches, an externally supplied input, and a
non-divisible-dimension case), so nothing may be hard-coded to the visible
fixture.

## Environment

- Working directory `/app`; Python 3.12 with torch and numpy preinstalled.
- Read-only shipped fixture: `/app/config.json` with keys `in_features`,
  `out_features`, `world_size`, `seed`, `batch`.
- Do not modify `/app/config.json`. Never read or touch `/tests` or
  `/solution`.

## Deliverables

1. `/app/tp_linear.py` — importable module defining `ColumnParallelLinear`
   (below) plus the validation CLI (below).
2. `/app/validate.json` — produced by running
   `python3 /app/tp_linear.py --config /app/config.json --out /app/validate.json`.

## Layer contract (must be followed exactly)

`/app/tp_linear.py` must define a `torch.nn.Module` subclass:

```python
class ColumnParallelLinear(torch.nn.Module):
    def __init__(self, in_features, out_features, world_size, bias=True): ...
```

- Raises `ValueError` unless `out_features % world_size == 0`.
- Parameters (created in this order): `self.weight`, a
  `torch.nn.Parameter` of shape `(out_features, in_features)` initialized with
  `torch.nn.init.normal_(self.weight, std=0.02)`; then, if `bias=True`,
  `self.bias`, a `torch.nn.Parameter` of shape `(out_features,)` initialized
  to zeros. No other parameters or RNG consumption.
- `shard_size()` returns `out_features // world_size`.
- `weight_shard(rank)` returns the rank's row block of the weight,
  `weight[rank*shard : (rank+1)*shard, :]` — shape `(shard_size,
  in_features)`. `bias_shard(rank)` similarly returns the rank's bias slice.
- **`forward(x)`** — `x` of shape `(B, in_features)`: compute each rank's
  local block `local_r = x @ weight_shard(r)^T + bias_shard(r)` (bias only if
  the layer has one), **all-gather** the blocks with
  `torch.cat(locals, dim=-1)` along the output dimension, and return the
  `(B, out_features)` result. The computation must be real sharded matmuls +
  concatenation — implemented so that, to machine precision, it equals
  `torch.nn.functional.linear(x, self.weight, self.bias)` (max abs diff
  `< 1e-5`), and stays differentiable w.r.t. `x`, `weight`, and `bias`.
- **`sharded_grad_weight(x, grad_output, rank)`** — returns the rank's exact
  slice of the dense weight gradient `grad_output^T @ x`:
  `(grad_output.T @ x)[rank*shard : (rank+1)*shard, :]`, shape
  `(shard_size, in_features)`.
- **`sharded_grad_bias(grad_output, rank)`** — returns the rank's slice of
  `grad_output.sum(dim=0)` (the dense bias gradient), shape `(shard_size,)`;
  return a zero-length-aware empty tensor is NOT allowed — if `bias=False`,
  raise `RuntimeError`.

Everything runs on CPU with default float32 dtype.

## Validation CLI

```
python3 /app/tp_linear.py --config <config.json> --out <out.json> [--input x.npy]
python3 /app/tp_linear.py --validate --in-features IN --out-features OUT --world-size W --seed S --batch B --out <out.json> [--input x.npy]
```

(The first form reads the geometry from the config JSON; the second form is
the same validation with explicit values. `--input` supplies the input `x` as
a `.npy` array of shape `(batch, in_features)`.)

Procedure:

1. If `out_features % world_size != 0`, write
   `{"ok": false, "reason": "nondivisible_output", "out_features": OUT,
   "world_size": W}` and exit 0.
2. Otherwise construct the layer: `torch.manual_seed(seed)` **immediately
   before** constructing `ColumnParallelLinear(in_features, out_features,
   world_size)` (no other RNG consumption first).
3. Build the input `x`:
   - if `--input` is given, load the `(batch, in_features)` float32 array
     (consume no RNG);
   - otherwise `torch.manual_seed(seed + 1)` and
     `x = torch.randn(batch, in_features)`.
4. Build the gradient `g` of the layer output's shape:
   `torch.manual_seed(seed + 2)`, `g = torch.randn(batch, out_features)`.
5. Compute and write JSON with exactly these keys:
   ```json
   {"ok": true, "world_size": W, "in_features": IN, "out_features": OUT,
    "seed": S, "batch": B,
    "forward_max_abs_diff": <float>,
    "grad_weight_max_abs_diff": <float>,
    "grad_bias_max_abs_diff": <float>,
    "y_col": [<flattened sharded forward output, rounded to 6 decimals>]}
   ```
   where
   - `forward_max_abs_diff` = max abs difference between `forward(x)` and
     `F.linear(x, weight, bias)` (must be `< 1e-5`);
   - `grad_weight_max_abs_diff` = max abs difference between the
     concatenation of `sharded_grad_weight(x, g, r)` over all ranks and the
     dense `g.T @ x` (must be `< 1e-5`);
   - `grad_bias_max_abs_diff` = same vs `g.sum(dim=0)` using
     `sharded_grad_bias` (must be `< 1e-5`);
   - `y_col` is the sharded forward output flattened row-major, each value
     `round(v, 6)`.
6. Exit 0 in both cases.

## Edge cases probed by hidden configurations

- Non-divisible `out_features % world_size` → the `ok:false` report above,
  exit 0, no crash.
- A single-input batch (`batch == 1`) and a `world_size` equal to
  `out_features` (shard size 1).
- An external `--input` array (the layer must not reseed or regenerate `x`).
- Sharded weights/gradients must reconstruct the dense tensors **exactly**
  (concatenation over ranks in rank order, no reordering).

## Constraints

- Deterministic (fixed seeds; no other randomness); no network access.
- `/app/tp_linear.py` must stay importable (CLI guarded under
  `if __name__ == "__main__":`).
