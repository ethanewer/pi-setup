# glass-mantle — gated set pooling for Hollowfield Robotics

Hollowfield Robotics summarizes LiDAR clusters: each cluster is a *set* of
point-feature rows that must be collapsed into one embedding by a learned
attention gate, then mapped to a descriptor. You must implement the pooling
module, `/app/setpool.py`, and run it on the shipped cluster catalog to produce
`/app/pooled.json`.

The grader imports `/app/setpool.py` and exercises it on **hidden
configurations** (different dimensions, seeds, batched sets, a single-element
set, and an **empty set**), so nothing may be hard-coded to the visible
fixture.

## Environment

- Working directory `/app`; Python 3.12 with torch and numpy preinstalled.
- Read-only shipped fixtures: `/app/config.json` (keys `in_dim`, `attn_dim`,
  `out_dim`, `seed`) and `/app/clusters.npz` (key `"X"`, float32 array of shape
  `(bag, in_dim)`).
- Do not modify `/app/config.json` or `/app/clusters.npz`. Never read or touch
  `/tests` or `/solution`.

## Deliverables

1. `/app/setpool.py` — importable module defining `GatedSetPooling` (below) and
   a CLI (below).
2. `/app/pooled.json` — produced by running the CLI on the visible fixture:
   ```
   python3 /app/setpool.py --config /app/config.json --clusters /app/clusters.npz --out /app/pooled.json
   ```

## Module contract (must be followed exactly)

`/app/setpool.py` must define a `torch.nn.Module` subclass:

```python
class GatedSetPooling(torch.nn.Module):
    def __init__(self, in_dim, attn_dim, out_dim): ...
```

creating, **in this exact order**, exactly these three layers (they are
checked by name):

- `self.proj = torch.nn.Linear(in_dim, attn_dim)`
- `self.score = torch.nn.Linear(attn_dim, 1)`
- `self.head = torch.nn.Linear(in_dim, out_dim)`

and these two methods:

- **`attention(self, x)`** — `x` is a rank-3 tensor `(B, bag, in_dim)` or a
  rank-2 tensor `(bag, in_dim)`. Compute
  `logits = self.score(torch.tanh(self.proj(x)))` and return
  `torch.softmax(logits, dim=<set axis>)`:
  - rank-2 input → softmax over `dim=0`, returning shape `(bag, 1)`;
  - rank-3 input → softmax over `dim=1`, returning shape `(B, bag, 1)`.
  For an **empty set** (`bag == 0`, rank-2 only) return an empty `(0, 1)`
  tensor instead of calling softmax.
- **`forward(self, x)`** — returns the tuple `(pooled, weights)` where
  `weights = self.attention(x)` and
  - rank-2 input: `pooled = self.head((x * weights).sum(dim=0))`, shape
    `(out_dim,)` (1-D);
  - rank-3 input: `pooled = self.head((x * weights).sum(dim=1))`, shape
    `(B, out_dim)`;
  - empty set (rank-2, `bag == 0`): the masked sum is an all-zero `(in_dim,)`
    vector, so `pooled = self.head(torch.zeros(in_dim))` — shape `(out_dim,)`,
    `weights` empty `(0, 1)`.

All computation on CPU, default float32 dtype, no dropout, no extra layers or
biases beyond the three Linear layers above.

## CLI contract

`python3 /app/setpool.py --config <config.json> --clusters <clusters.npz> --out <out.json>`
must:

1. Load the config JSON (`in_dim`, `attn_dim`, `out_dim`, `seed`).
2. Execute `torch.manual_seed(seed)` **immediately before** constructing
   `GatedSetPooling(in_dim, attn_dim, out_dim)` (no other RNG consumption
   before or between the three layer constructions).
3. Load `X` from the `.npz` as a float32 tensor, run `forward` under
   `torch.no_grad()`, and write JSON with exactly these keys:
   ```json
   {"pooled": [<out_dim> floats], "weights": [<bag> floats], "bag": <bag int>}
   ```
   `weights` is the flattened per-element attention (empty list when
   `bag == 0`).

## Edge cases probed by hidden configurations

- **Batched sets** (rank-3 `(B, bag, in_dim)`): each set's weights must sum to
  `1` over its bag axis (within `1e-4`); `pooled` shape `(B, out_dim)`.
- **Single-element set** (`bag == 1`): the weight must be exactly `1.0`.
- **Empty set** (`bag == 0`, rank-2): must not crash; `weights` empty and
  `pooled = head(zeros)`.
- Hidden numeric checks compare `pooled` and `weights` against an independent
  reference implementing exactly the contract above under the same seed, to
  `1e-4`.

## Constraints

- Deterministic; no network access; torch + numpy only.
- `/app/setpool.py` must stay importable (guard any CLI execution under
  `if __name__ == "__main__":`).
