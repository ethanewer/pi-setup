# Reconstruct a tiny causal transformer engine from its state dict

## Goal

A small decoder-style causal transformer was trained to assign a real-valued score to a token
sequence. You are given its hyperparameters and its raw weight tensor, but no
model code. You must write **one compact, dependency-free engine** in Python that:

1. **Reconstructs** the transformer architecture from the state dictionary,
2. **Runs inference** to produce exactly one score per input sequence,
3. **Persists a low-rank factorization** of every linear weight matrix of the model.

The finished deliverables live in `/app` and are read out by a grading harness.

## Environment

- Everything is provided under `/app/fixtures/`:
  - `/app/fixtures/model.json` — architecture hyperparameters.
  - `/app/fixtures/state.npz` — the model's raw weights (numpy arrays, `float32`).
  - `/app/fixtures/data.json` — the scoring set: a JSON array of `[sample_id, [token_ids]]`.
- Python 3.12 with `numpy` is available. That is all you may use in your engine
  (**no** torch, triton, scipy, or any other third-party package).

## Deliverables

Create these three files:

1. `/app/reconstruct.py` — the reusable, argument-driven engine (see CLI below).
2. `/app/preds.csv` — predictions computed by running your engine on the fixtures.
3. `/app/lowrank.npz` — the low-rank factorization produced by running your engine
   on the fixtures.

The grading harness re-runs your `/app/reconstruct.py` on **other** (hidden) fixture sets
whose hyperparameters differ (depth, width, vocab, context length, head count, rank).
Your engine must therefore be **architecture-parametric**: it must derive every tensor
shape and the number of layers *from* `model.json` / `state.npz`, never hard-code the
visible fixture's dimensions.

## CLI contract (exact)

```
python3 reconstruct.py <CONFIG> <STATE> <DATA> --out <PREDS_CSV> --lowrank <LOWRANK_NPZ>
```

- `<CONFIG>` — path to a `model.json`.
- `<STATE>` — path to a `state.npz`.
- `<DATA>` — path to a `data.json`.
- `--out` — path to write the prediction CSV (default `preds.csv`).
- `--lowrank` — path to write the low-rank `.npz` (default `lowrank.npz`).

The harness will call your script with its own absolute input paths. It must work from any
working directory and must not read hard-coded absolute fixture paths, the working
directory, or any file you are not told about. Exit code 0 on success.

## Hyperparameters (`model.json`)

```json
{"d": 8, "ff": 16, "heads": 2, "layers": 2, "ctx": 6, "vocab": 30, "rank": 3}
```

- `d` — model width (embedding dim = hidden dim).
- `ff` — feed-forward intermediate width.
- `heads` — number of attention heads; `d // heads` is the per-head dim.
- `layers` — number of transformer blocks.
- `ctx` — maximum sequence length (positional embedding rows).
- `vocab` — vocabulary size.
- `rank` — the intended matrix rank for the low-rank outputs.

## Weight layout (`state.npz`, all `float32`)

- `embed`: `(vocab, d)` token embedding.
- `pos`: `(ctx, d)` positional embedding.
- For each block `i` in `0 .. layers-1`:
  - `q<i>`, `k<i>`, `v<i>`, `o<i>`: `(d, d)` attention projection weights.
  - `w1<i>`: `(d, ff)` and `w2<i>`: `(ff, d)` feed-forward weights.
- `ln_g`, `ln_b`: `(d,)` final LayerNorm scale & shift (applied once, on the last token).
- `out`: `(d,)` scalar head weight vector; `bout`: `()` scalar head bias.

For `layers == 2` the tensors are `q0,k0,v0,o0,w10,w20,q1,k1,v1,o1,w11,w21`.

## Forward pass (must be reproduced exactly)

To score a single token sequence `p` of length `T` (an array of `T` token ids):

1. `x = embed[p]` (rows for the tokens) **+** `pos[:T]` (row `i` added to token position `i`).
   Do all arithmetic in `float32`.
2. `dh = d // heads`.
3. For each block `i` in sequence:
   - **Pre-normalize** every row of `x` (that is, for a row, over its `d` features):
     `n = (x - mean) / sqrt(var + 1e-5)`, where both `mean` and `var` (population
     variance, `ddof=0`) are computed over the feature axis.
   - `q = n @ q<i>`, `k = n @ k<i>`, `v = n @ v<i>` (each `T x d`).
   - Reshape each of `q`, `k`, `v` to `(T, heads, dh)` then transpose to `(heads, T, dh)`.
   - `att = q @ k.T / sqrt(dh)` (per head; `k.T` swaps the two sequence axes of the head).
   - Softmax `att` over the last axis (`exp(x - max) / sum(exp(x - max))`).
   - `o = att @ v` -> reshape back to `(T, d)` (undo the head split).
   - `x = x + o @ S['o' + i]` (the `o<i>` projection weight for block `i`).
   - `h = x @ S['w1' + i]`; apply GELU (tanh approximation):
     `g = 0.5 * h * (1 + tanh( sqrt(2/pi) * (h + 0.044715 * h**3) ))`.
   - `x = x + g @ S['w2' + i]`.
4. Take the last-token row `z = x[T-1]`. Normalize it as a single vector with the same
   `sqrt(var + 1e-5)` formula, then `z = z * ln_g + ln_b`.
5. `score = dot(z, S['out']) + S['bout']`.

Attention is **full** (bidirectional) — there is no causal mask.

## Prediction output (`preds.csv`)

- Header line exactly: `sid,score`
- One line per sample, in the **same order** as in `data.json`.
- Each line: `<sample_id>,<score>` where the score is written with exactly 8 decimals.
- The score must be a real number; scores across samples must **not** all be equal.

## Low-rank output (`lowrank.npz`)

For **every 2D linear weight matrix** of the model (this includes `embed` and `pos`,
and for each block the `q`, `k`, `v`, `o`, `w1`, `w2` matrices) store two arrays:

- `<matrixname>_L` of shape `(rows, r')`
- `<matrixname>_R` of shape `(r', cols)`

such that `<matrixname>_L @ <matrixname>_R` is a rank-`r'` approximation of the
original matrix. Use `r' = min(rank, rows, cols)` for each matrix. Save the `.npz` with
`np.savez_compressed`.

Low-rank requirement enforced by the harness: for every matrix
`M = L @ R`, the number of singular values of `M` larger than `1e-4 * (its largest
singular value)` must be at most `rank` (and at least 1). A standard truncated SVD
(the top-`r'` singular vectors) satisfies this exactly.

Suggested scheme: `U, sv, Vt = np.linalg.svd(M.astype(np.float64), full_matrices=False)`;
`L = U[:, :r'] * sv[:r']`; `R = Vt[:r', :]`; store `L` and `R` (as `float32`).

## Source-size (byte) budget

`reconstruct.py` must compile cleanly with `python3 -m py_compile` and its raw source
**must be at most `6000` bytes** (`wc -c`). Keep it compact and dependency-free.

## Hard constraints

- Do **not** modify `/app/fixtures/` or read the harness's grading files.
- Produce the three deliverables by running the engine (do not fabricate output literals).
- Use **only** Python standard library + `numpy`.
- Exit 0 and produce all outputs on any valid input set whose hyperparameters follow the
  above schema.