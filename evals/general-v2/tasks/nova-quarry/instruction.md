# Fit a next-token transformer engine under a strict source-size budget

Orbital-9 Avionics ships a tiny causal transformer that scores the next token of
a short token sequence. The trained weights are available, but the inference
code was lost. You must re-implement the **entire forward pass** — embeddings,
attention blocks, normalization, and the vocabulary projection — as one compact,
dependency-free Python program whose source fits a strict byte budget.

## Environment

- Everything is under `/app/fixtures/`:
  - `/app/fixtures/model.json` — architecture hyperparameters.
  - `/app/fixtures/state.npz` — raw weights (numpy arrays, `float32`).
  - `/app/fixtures/data.json` — a JSON array of `[sample_id, [token_ids]]`.
- Python 3.12 with `numpy` is installed. That is the only third-party package
  you may use (no torch, no scipy, nothing else).

## Deliverables (both required)

1. `/app/engine.py` — the engine (see CLI contract below).
2. `/app/preds.csv` — predictions produced by running your engine on the
   visible fixtures:
   ```
   python3 /app/engine.py /app/fixtures/model.json /app/fixtures/state.npz /app/fixtures/data.json --out /app/preds.csv
   ```

### CLI contract (exact)

```
python3 /app/engine.py <CONFIG> <STATE> <DATA> --out <PREDS_CSV>
```

It must work from any working directory and must not hard-code the visible
fixture's dimensions, file names, or contents. Exit code 0 on success.

### Source-size budget (hard)

The raw source of `/app/engine.py` must be **at most 3000 bytes** as measured by
`wc -c < /app/engine.py`, and it must compile cleanly with the mandated command

```
python3 -m py_compile /app/engine.py
```

Overshooting the byte cap or failing to compile with that exact command is a
failure regardless of prediction correctness.

## Hyperparameters (`model.json`)

```json
{"d": 12, "ff": 24, "heads": 3, "layers": 2, "ctx": 10, "vocab": 40}
```

- `d` — model width (embedding dim = hidden dim); `d // heads` is per-head dim.
- `ff` — feed-forward intermediate width.
- `layers` — number of transformer blocks.
- `ctx` — maximum sequence length (positional embedding rows).
- `vocab` — vocabulary size.

## Weight layout (`state.npz`, all `float32`)

- `embed`: `(vocab, d)` token embedding; `pos`: `(ctx, d)` positional embedding.
- For each block `i` in `0 .. layers-1`:
  - `q<i>`, `k<i>`, `v<i>`, `o<i>`: `(d, d)` attention projection weights.
  - `w1<i>`: `(d, ff)`; `w2<i>`: `(ff, d)` feed-forward weights.
- `ln_g`, `ln_b`: `(d,)` final LayerNorm scale and shift.
- `wout`: `(d, vocab)` vocabulary projection; `bout`: `(vocab,)` output bias.

## Forward pass (must be reproduced exactly; all arithmetic in `float32`)

For a token sequence `t` of length `T` (2 <= T <= ctx):

1. `x[i] = embed[t[i]] + pos[i]` for each position `i`, giving `(T, d)`.
2. For each block `i` in order:
   - **Pre-normalize**: for each row, with `mean` and population variance
     (`ddof=0`) over its `d` features:
     `n = (x - mean) / sqrt(var + 1e-5)`.
   - `q = n @ q<i>`, `k = n @ k<i>`, `v = n @ v<i>` (each `(T, d)`).
   - Reshape each to `(T, heads, dh)`, transpose to `(heads, T, dh)`.
   - `att = q @ k^T / sqrt(dh)` per head (`k^T` swaps the two sequence axes).
   - **Causal mask**: `att[a][b] = -1e30` for every `b > a` (applied before
     softmax). There are no other masks.
   - Softmax over the last axis: `exp(a - max) / sum(exp(a - max))` where `max`
     is the row maximum.
   - `merged = (att @ v)` transposed back to `(T, d)` (undo the head split).
   - `x = x + merged @ o<i>`.
   - `h = x @ w1<i>`; `h = max(h, 0)` (ReLU); `x = x + h @ w2<i>`.
3. Take the last-token row `z = x[T-1]`, normalize it with the same
   `sqrt(var + 1e-5)` formula, then `z = z * ln_g + ln_b`.
4. `logits = z @ wout + bout` (a vector of length `vocab`).
5. `pred_token = argmax(logits)`; `top_logit = max(logits)`.

## Prediction output (`preds.csv`)

- Header line exactly: `sid,pred_token,top_logit`
- One line per sample, in the **same order** as `data.json`.
- Each line: `<sample_id>,<pred_token>,<top_logit>` with `top_logit` written
  with exactly 6 decimals.
- Predictions must not all be identical across samples.

## Edge cases the verifier probes

- Different architecture hyperparameters than the visible fixture (deeper or
  shallower stacks, other widths/head counts/vocab sizes/context lengths).
- Sequence lengths from 2 up to `ctx`.
- Tokens spanning the full vocabulary range.
- The engine must derive **every** tensor shape and the layer count from
  `model.json` / `state.npz` — never hard-code the visible dimensions.

## Hard constraints

- Standard library + `numpy` only.
- Do not modify `/app/fixtures/` or read the grader's files.
- The verifier re-runs `/app/engine.py` unchanged on hidden fixture sets and
  enforces the byte budget and the mandated compile command.
