# tundra-ledge — ML systems solver

Write a single executable Python program `/app/solve.py` that solves three
independent ML problems against the fixtures already placed in `/app` and writes
`/app/answer.json`. Everything is CPU-only. Do not modify the fixtures.

Your `/app/solve.py` MUST expose three importable, general-purpose functions; the
verifier re-runs those functions on fresh (hidden) inputs to confirm your code is
a real algorithm rather than a fixed answer. Each function must therefore handle
arbitrary new inputs of the documented shapes, including edge cases.

## Deliverables

1. `/app/solve.py` — when run (`python3 /app/solve.py`) it performs the three
   tasks on the `/app` fixtures and writes `/app/answer.json`.
2. `/app/answer.json` — JSON with exactly these keys:
   - `"mlp_rows"` : list of equal-length lists of floats — your recovered matrix.
   - `"lowrank_matrix"` : list of lists of floats — your full matrix.
   - `"lowrank_rows"`, `"lowrank_cols"`, `"lowrank_rank"` : ints.
   - `"chess_state_path"` : the string `"chess_state.pt"`.
3. `/app/chess_state.pt` — a PyTorch `state_dict` (dict of `str -> Tensor`)
   built from `/app/chess_net.cnet`, written with `torch.save`.

## Problem A — interrogate & recover a black-box ReLU MLP

`/app/blackbox.py` loads a class `BlackBox`. Instantiate it:

```python
from importlib import spec_from_file_location, module_from_spec
spec = spec_from_file_location("blackbox", "/app/blackbox.py")
mod = module_from_spec(spec); spec.loader.exec_module(mod)
model = mod.BlackBox()
```

The model computes a scalar
```
f(x) = sum_i  v_i * relu(W_i · x + b_i)
```
with unknown input rows `W_i`. `model.query(x)` returns `float` for any
array-like `x` of length `model.in_dim`. **The only permitted channel is
`model.query`**. The rows you want are the products `v_i * W_i`; they will not be
obtainable from any visible attribute.

Recovery contract: your matrix may be **row-permuted and each row scaled by an
arbitrary constant (including -1)**; under those two ambiguities every true row
`v_i*W_i` must be matched by one of your rows to within a small tolerance.

Hint (not mandatory): along `x = t*e_d` the model is convex piecewise-linear in
`t`; each unit crosses its kink hyperplane at `t = -b_i / W_i[d]`, and at that
crossing the full numerical gradient changes by exactly the signed row
`v_i*W_i`. Handle the sign and permutation ambiguity explicitly.

Expose a fully general routine (input dimension and unit count vary):

```python
def extract_mlp(query, in_dim):
    """
    query : callable, returns float for an array of length in_dim
    returns : np.ndarray of shape (n_units, in_dim) recovering v_i*W_i rows
    """
```

## Problem B — low-rank matrix completion

`/app/lowrank_obs.json`:
```json
{ "m": 40, "n": 40, "rank": 3, "obs": [[row, col, value], ...] }
```
The sparse `obs` are samples of a hidden matrix M (m x n) that is **exactly
low rank**. Reconstruct a full m x n matrix that (a) is close to M and (b) is
itself **low-rank (at most a handful of significant singular values, capped by
`rank`)**. A working method is alternating projection (iteratively hard-threshold
a filled estimate to `rank`, re-clamp observed entries; final output must be a
rank-`rank`/low matrix — do not return overfitted dense noise).

Expose:
```python
def complete_matrix(obs_dict):
    """obs_dict: {"m","n","rank","obs":[[r,c,v],...]} -> np.ndarray (m,n), low-rank."""
    ...
```

## Problem C — chess network conversion

Build the PyTorch network `ChessNet` with the weights taken from the packed
`/app/chess_net.cnet`:

```
conv1: Conv2d(1->16, kernel 3, pad 1)   weight (16,1,3,3)   bias (16,)
conv2: Conv2d(16->24, kernel 3, pad 1)  weight (24,16,3,3)  bias (24,)
conv3: Conv2d(24->32, kernel 3, pad 1)  weight (32,24,3,3)  bias (32,)
fc1:   Linear(32->8)                    weight (8,32)       bias (8,)
head:  Linear(8->1)                     weight (1,8)        bias (1,)
```

The container `/app/chess_net.cnet` (named `NNT1`, our own invented format) is:
after the 4-byte magic `b"NNT1"` and a `uint32` tensor count, each tensor is:

```
u8 kind          (1 = weight, 2 = bias)
u8 name-length   then that many name bytes e.g. b"conv1.weight"
u8 codec         (1 = int8 quantized, 2 = raw float32)
u32 dims-count   then that many u32 dims
u32 n
if codec==1:  f32 scale, then n signed int8 bytes ; value = int8_array * scale
if codec==2:  n little-endian float32 bytes
... end: one u8 sentinel 0xFF
```

Reconstruct each tensor, assemble the `ChessNet` state dict, and `torch.save`
it to `/app/chess_state.pt`. The dict must load into a `ChessNet` (all ten
parameters) and `forward` must produce finite output on a `2x1x8x8` input.

Expose (raise `ValueError` on malformed input):

```python
def convert_chessnet(path):
    """-> OrderedDict {param_name: torch.Tensor}"""
```

The verifier re-runs this on a `.cnet` describing a **different (smaller)** chess
architecture with the same container format — read dims/names/datatype from the
file, never hard-code the specific shapes.

---

## Constraints

- Write your outputs only under `/app`; leave the `/app` fixtures untouched.
- Return finite floats everywhere. No network access is required.
- A short completion message on stdout is welcome but optional.
- Correctness and generalization are what matter; a few minutes of compute are
  fine. Do not import extra heavy libraries beyond what is present.