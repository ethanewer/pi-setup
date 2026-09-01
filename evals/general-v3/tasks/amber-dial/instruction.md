# amber-dial — the Nighthollow small-model serving layer

## Objective

The lattice team at **Nighthollow** keeps a small on-device recommender engine.
Your job is to author a single self-contained Python program, `/app/solve.py`,
that supplies the whole serving layer for it, and to run it so that it writes
`/app/answer.json`. The program must:

1. Implement two hand-rolled **tensor-parallel (model-parallel) linear layers**
   whose forward outputs *and* sharded weight gradients are numerically
   identical to an ordinary dense linear layer:
   - `RowParallelLinear` — the weight split along the **input** dimension; each
     of `world_size` ranks holds a column block of the weight and computes a
     partial product; the per-rank partials are all-reduced (summed); the full
     bias is added on every rank.
   - `ColumnParallelLinear` — the weight split along the **output** dimension;
     each rank computes a local output block; the blocks are all-gathered
     (concatenated) along the output dimension and the full bias is added. It
     must also expose a sharded-gradient routine returning, per rank, the exact
     slice of the dense weight gradient.
2. Build a two-head forward engine, `PolicyWDLEngine`, whose `forward` returns
   a dict with at least the keys:
   - `policy_logits` — `(B, NUM_LEGAL_MOVES)` raw logits (no softmax), and
   - `value` — `(B, 3)` **post-softmax** outcome probabilities
     (`[loss, draw, win]`), so every value row sums to (about) 1.
   The engine's interior must be wired from your `RowParallelLinear` and
   `ColumnParallelLinear` layers.
3. Expose a **Flask** `POST /classify` endpoint returning a structured
   classification result (label + per-class confidence object) with the exact
   schema and behavior described below.

## Deliverables

- `/app/solve.py` — your implemented program (executable, invoked via
  `python3 /app/solve.py`). Every invocation mode (default report, `--infer`,
  `--serve`) must start promptly and terminate/produce its output within about
  a minute; a run that hangs or exceeds this is treated as a failure.
- `/app/answer.json` — produced by running `/app/solve.py`; a JSON report that
  satisfies the checks below.
- `/app/model.pt` — a PyTorch checkpoint of your trained `PolicyWDLEngine`
  (written by your program; needed by the `--infer` mode).

## Fixed architecture constants

```
NUM_LEGAL_MOVES = 2156   # width of the policy (legal-move) head
IN_FEATURES     = 64     # dimension of one input feature vector
HIDDEN          = 128    # internal hidden width of the engine
WORLD_SIZE      = 8      # number of parallel ranks the engine is sharded across
```

## Requirements

### 1. Parallel linear layers

Implement both layers as `torch.nn.Module` subclasses. For the purposes of this
task the container is single-process; the "ranks" are virtual slices that you
walk inside `forward`. Concretely:

- `RowParallelLinear(in_features, out_features, world_size, bias=True)`:
  - Stores a full weight `W` of shape `(out_features, in_features)` and bias
    `(out_features,)`. Weight init: `torch.randn(out_features, in_features) *
    0.05`; bias init `torch.zeros(out_features)`.
  - Raises `ValueError` unless `in_features % world_size == 0`.
  - `forward(x)` returns `x @ W^T + bias` **computed by** splitting `x` and `W`
    into `world_size` input-dimension chunks, computing each partial
    `x_r @ W_r^T`, all-reducing (summing) the partials, and adding the bias.
  - Provide `sharded_grad_weight(x, grad_of_out, rank)` returning
    `grad_of_out^T @ x_reduced`, the chunk of the dense `dL/dW` owned by that
    rank's column block.
- `ColumnParallelLinear(in_features, out_features, world_size, bias=True)`:
  - Same weight/bias init as above.
  - Raises `ValueError` unless `out_features % world_size == 0`.
  - `forward(x)` returns `x @ W^T + bias` computed by computing each rank's
    `local = x @ W_r^T` block, all-gathering (concatenating) those blocks along
    the output dimension, then adding the bias.
  - Provide `sharded_grad_weight(x, grad_of_out, r)` returning the rank's row
    slice of the dense `dL/dW`.

Both layers must satisfy: for any live input, `forward(x)` equals
`torch.nn.functional.linear(x, W, bias)` and, for a gradient `g` of the same
shape as the output, the concatenation of all ranks’ `sharded_grad_weight`
equals `g^T @ x`, all to machine precision.

### 2. The forward engine

- `class PolicyWDLEngine(in_features=64, hidden=128, world_size=8,
  num_moves=2156)`.
- Build the stem with your `ColumnParallelLinear` then `RowParallelLinear`
  layers (e.g. `ColumnParallelLinear(in_features, hidden, world_size)` followed
  by `RowParallelLinear(hidden, hidden, world_size)`), with ReLU and a
  `LayerNorm`.
- `forward(x)` returns the dict described above. Train it on a tiny separable
  synthetic dataset of your own construction (features `(B, 64)`),
  deterministically generated inside the program (use fixed seeds). Report
  training top-1 accuracy for both heads in `answer.json`. Aim for both accuracies
  at or above **0.5** and a value head whose rows sum to 1.

### 2. `answer.json`

Running `python3 /app/solve.py` with no arguments must:
- train the engine, write `/app/model.pt` (state_dict),
- run a parallel-layer validation comparing `RowParallelLinear` /
  `ColumnParallelLinear` with dims `IN_FEATURES×HIDDEN`, world 8 against the
  dense reference on a fixed small input, and
- write `/app/answer.json` with (exact keys):

```json
{
  "arch": {"in_features":64,"hidden":128,"world_size":8,"num_moves":2156},
  "train": {"policy_top1_accuracy": <float>, "value_top1_accuracy": <float>},
  "forward": {"value_rowsum_max_abs_err": <float>},
  "parallel": {
    "ok": true,
    "row_forward_max_abs_diff": <tiny>, "col_forward_max_abs_diff": <tiny>,
    "row_grad_max_abs_diff": <tiny>,    "col_grad_max_abs_diff": <tiny>
  },
  "flask_empty_label": "neutral",
  "model_saved": "/app/model.pt"
}
```

All four `parallel.*_max_abs_diff` values must be `< 1e-4`.

### 3. Flask `/classify`

`/app/solve.py` must, when run as `python3 /app/solve.py --serve <port>`, start
a HTTP server on `127.0.0.1:<port>` with a `POST /classify` endpoint. The
schema and classifier are **fully specified** so the verifier re-derives them:

- **Lexicons** (a word is matched on lower-cased alphabetic token, exactly):
  - POSITIVE = `good great excellent fast clean strong stable improved brilliant liked`
  - NEGATIVE = `bad worst poor slow broken fail late drop clunky buggy`
  - NEUTRAL  = `okay fine average same normal steady`
- **Tokens**: `re.findall(r"[a-z']+", text.lower())`.
- Let `pos/neg/neu` be the counts of hits in each lexicon.
- **label**:
  - if `pos > neg` → `"positive"`;
  - else if `pos < neg` → `"negative"`;
  - else → `"neutral"` if `neu > 0`, otherwise `"positive"`.
- **confidence**: add-one-smoothed relative frequencies
  `raw_c = count_c + 1`, `total = sum(raw)`,
  `confidence[c] = round(raw_that / total, 6)` for the three keys
  `positive, negative, neutral`.
- **empty / whitespace text** → a fixed neutral result:
  `{"label":"neutral","confidence":{"positive":0.333333,"negative":0.333333,"neutral":0.333333}}`.

Request handling:
- `Content-Type` must be `application/json`; a non-JSON body → HTTP 400 with a
  JSON body `{"error": "content-type-not-json"}`.
- The JSON body must be a mapping containing a string field `text`; otherwise →
  HTTP 400 with `{"error": "missing-text"}`.
- Otherwise → HTTP 200 with `{"label": ..., "confidence": {...}}` as above.

### 3. CLI modes the verifier invokes

- `python3 /app/solve.py` — default: train engine, write `/app/model.pt` and
  `/app/answer.json` (as above).
- `python3 /app/solve.py --validate-parallel --in-features IN --out-features
  OUT --world-size W --seed S --batch B [--input path.npy]`
  - If `IN % W != 0` → print `{"ok": false, "reason":
    "nondivisible_input", ...}` and exit 0.
  - Else if `OUT % W != 0` → print `{"ok": false, "reason":
    "nondivisible_output", ...}` and exit 0.
  - Else construct the two layers with `torch.manual_seed(S)` then the `--seed`
    init order (row layer first, then column layer), and if `--input` is given
    load its `(batch, in_features)` `.npy` as `x` (no RNG consumed before the
    layers); otherwise use `torch.manual_seed(S); x = torch.randn(batch, in)`.
    Print one JSON object with keys: `ok`,
    `world_size / in_features / out_features / seed`,
    `row_forward_max_abs_diff`, `col_forward_max_abs_diff`,
    `row_grad_max_abs_diff`, `col_grad_max_abs_diff` (each `< 1e-4`),
    and a flattened list `y_row` (the row-parallel forward output, float32
    rounded to 6 decimal places, row-major over the batch). Exit 0.
- `python3 /app/solve.py --infer <features.npy>` — loads `/app/model.pt`, runs
  the engine on the `(N,64)` float32 array, prints one JSON object:
  `{"n_inputs": N, "in_features": 64,
    "policy_logits_shape":[N,2156], "value_shape":[N,3],
    "value_rowsum_max_abs_err": float( max(|rowsum-1|) , or 0.0 when N==0),
    "policy_finite": bool, "all_in_unit_interval": bool}`.
  - If the array is not shaped `(., 64)` print
    `{"error":"bad-shape", ...}` and exit non-zero (e.g. 2).

## Edge cases the verifier probes (hidden)

- `--validate-parallel` with an input dimension that is **not** divisible by the
  world size → `ok:false, reason:"nondivisible_input"`, exit 0.
- `--validate-parallel` with an output dimension not divisible by world size →
  `ok:false, reason:"nondivisible_output"`, exit 0.
- `--infer` on a `(0,64)` array → normal report with `n_inputs:0`, shapes
  `[0,2156]`/`[0,3]`, `value_rowsum_max_abs_err:0.0`, all flags `true`.
- `--infer` on a wrongly-sized array (not `(N,64)`) → non-zero exit and
  `{"error":"bad-shape", ...}`.
- `/classify` with an empty string → the fixed neutral triple.
- `/classify` with a non-JSON body or a JSON body lacking a string `text` field →
  HTTP **400** with a JSON error object.

## Constraints

- Torch, NumPy and Flask are already installed in the image. Python 3.12.
- `/app/solve.py` and `/app/answer.json` are the deliverables; `/app/model.pt`
  is required for `--infer`. All paths are literal (no environment indirection).
- You must not create or write anything under `/tests` (mounted read-only at
  verify time) — the program is graded purely by re-running it from `/app`.
- Keep the program deterministic (fixed random seeds) so every value reported in
  `answer.json` is reproducible from a fresh run.