# Relay-7 logits engine under a hard source budget

A tiny autoregressive transformer ("Relay-7") was trained to predict the next
vocabulary token for a token sequence. You are given its hyperparameters and its
raw weights, but **no model code**. You must write **one compact,
dependency-free Python engine** that reconstructs the architecture, runs
inference over a scoring set, and emits the predicted token plus its logit for
every sequence.

Everything lives under `/app`:

- `/app/fixtures/config.json` — architecture hyperparameters.
- `/app/fixtures/state.json` — raw weights (JSON, plain nested float lists).
- `/app/fixtures/data.json` — a JSON array of `[sample_id, [token_ids]]`.

Python 3.12 is available. Your engine may use **only the Python standard
library** — no numpy, no third-party packages of any kind.

## Deliverables

1. `/app/engine.py` — the reusable, argument-driven engine (CLI below).
2. `/app/preds.csv` — predictions produced by running your engine on the
   visible fixtures.

## CLI contract (exact)

```
python3 /app/engine.py <CONFIG> <STATE> <DATA> --out <PREDS_CSV>
```

- Reads the three JSON inputs from the given paths and writes the prediction
  CSV to `<PREDS_CSV>` (default `preds.csv` in the current directory when
  `--out` is omitted).
- Must work from any working directory and must not hard-code fixture paths or
  dimensions. Exit code 0 on success.

## Hyperparameters (`config.json`)

```json
{"d": 12, "ff": 32, "heads": 3, "layers": 2, "ctx": 8, "vocab": 40}
```

- `d` — model width; `heads` — attention heads (`dh = d // heads` per-head dim).
- `layers` — number of blocks; `ctx` — max sequence length; `vocab` — vocab size.
- `ff` — feed-forward intermediate width.

## Weight layout (`state.json`, plain nested lists)

- `embed`: `(vocab, d)` token embedding; `pos`: `(ctx, d)` positional embedding.
- For each block `i` in `0 .. layers-1`:
  - `qkv<i>`: `(d, 3d)` fused query/key/value projection (columns `0:d` = Q,
    `d:2d` = K, `2d:3d` = V).
  - `o<i>`: `(d, d)` attention output projection.
  - `w1<i>`: `(d, ff)`, `w2<i>`: `(ff, d)` feed-forward weights.
  - `ln1g<i>`, `ln1b<i>`: `(d,)` LayerNorm scale/shift applied before attention.
  - `ln2g<i>`, `ln2b<i>`: `(d,)` LayerNorm scale/shift applied before the
    feed-forward sub-layer.
- `lfg`, `lfb`: `(d,)` final LayerNorm scale & shift.
- `head`: `(d, vocab)` vocabulary projection matrix (no bias).

## Forward pass (reproduce exactly)

To score a token sequence of length `T`:

1. `x[i] = embed[token_i] + pos[i]` for each position `i` (float arithmetic).
2. For each block `i`:
   - **Pre-norm attention.** Normalize every row of `x` over its `d` features:
     `n = (row - mean) / sqrt(var + 1e-5)` (population variance, `ddof=0`),
     then `n = n * ln1g<i> + ln1b<i>`. Project `n @ qkv<i>` and split into
     `q`, `k`, `v` (each `T x d`). Per head, with `dh = d // heads`:
     `att = q_head @ k_head^T / sqrt(dh)`, **causally masked** (position `j > i`
     is excluded from row `i`), softmaxed with the stable form
     `exp(s - max) / sum(exp(s - max))`, then `out_head = att @ v_head`.
     Concatenate heads back to `(T, d)` and update `x = x + out @ o<i>`.
   - **Pre-norm feed-forward.** Normalize rows with `ln2g<i> / ln2b<i>`,
     `h = n2 @ w1<i>`, apply **SiLU** activation `silu(z) = z / (1 + exp(-z))`,
     and update `x = x + silu(h) @ w2<i>`.
3. Take the last-token row `z = x[T-1]`; normalize it with the same
   `sqrt(var + 1e-5)` formula, then `z = z * lfg + lfb`.
4. **Vocabulary projection:** `logits = z @ head` (a vector of `vocab` logits).
   `token` = the argmax index (the **first** index attaining the maximum on
   ties); `logit` = that maximum value.

## Output CSV (`preds.csv`)

- Header line exactly: `sid,token,logit`
- One line per sample, in the same order as `data.json`.
- Each line: `<sample_id>,<token>,<logit>` with the logit written to exactly
  6 decimal places.
- Tokens across samples must not all be identical.

## Source-size (byte) budget — hard requirement

`/app/engine.py` must compile cleanly with

```
python3 -m py_compile /app/engine.py
```

and its raw source must be **at most 5000 bytes** (`wc -c`). An engine that
overshoots the byte cap fails regardless of prediction quality. Keep it
compact: derive every shape from `config.json` / `state.json`, loop explicitly,
and avoid dead code.

## Generalization

The grader re-runs `/app/engine.py` unchanged on **hidden** fixture sets whose
hyperparameters differ (depth, width, vocab, context, head count, layer count).
Your engine must be fully architecture-parametric.

## Hard constraints

- Do not modify anything under `/app/fixtures/`.
- Produce `/app/preds.csv` by running the engine (no fabricated literals).
- Standard library only; no network access; deterministic output.
