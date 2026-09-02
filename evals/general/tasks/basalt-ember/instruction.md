# Run the pika-net MLP forward pass

You must write a self-contained Python program `/app/classify.py` that executes
the forward pass of a small two-layer neural network ("pika-net") whose learned
weights are shipped in a JSON file, and reports a predicted label plus the
per-class softmax scores for each input sample.

## Files provided (do NOT modify them)

- `/app/network.json` — the trained network parameters (schema below).
- `/app/samples.json` — a JSON **array** of feature vectors (each an array of
  real numbers), to classify in order.

Every network/sample pair produced by this contract uses the same schema. Your
program must work for ANY conforming pair, not just the provided one: the
verifier runs it unchanged on several hidden pairs.

## network.json schema

```json
{
  "standardize": {"mean": [...D...], "std": [...D...]},
  "hidden": {"w": [[...D...] x H], "b": [...H...]},
  "output": {"w": [[...H...] x C], "b": [...C...]}
}
```

- `D` = number of input features, `H` = hidden neurons, `C` = classes.
- `standardize` is **optional**: the key may be absent (see below).
- `hidden.w` has `H` rows of exactly `D` entries; `hidden.b` has `H` entries.
- `output.w` has `C` rows of exactly `H` entries; `output.b` has `C` entries.
- All values are real numbers; `C >= 1`, `D >= 1`, `H >= 1`.

## The forward pass (exact math)

For each input vector `x` (length `D`):

1. **Standardize** (only if the `standardize` key is present and not null):
   `x'[j] = (x[j] - mean[j]) / std[j]`, except when `std[j] == 0` you must use
   `1.0` as the divisor for that feature (no division by zero). If the key is
   absent, use `x` unchanged.
2. **Hidden layer** (tanh activation):
   `h[i] = tanh( sum_j Wh[i][j] * x'[j] + bh[i] )` for `i in [0, H)`.
3. **Output layer** (linear): `logit[c] = sum_i Wo[c][i] * h[i] + bo[c]`
   for `c in [0, C)`.
4. **Label**: `label = argmax(logit)`; on ties choose the **smallest** class
   index (a tie is valid input — never raise).
5. **Per-class scores**: softmax of the logits,
   `p[c] = exp(logit[c] - m) / sum_k exp(logit[k] - m)` where `m = max(logit)`.
   You MUST subtract the max before exponentiating (hidden cases contain
   logits large enough to overflow a naive `math.exp`).

## Output format

Write JSON to the output path:

```json
{"labels": [0, 2, ...], "probs": [[p0, p1, ...], ...]}
```

- one integer label and one probability vector (length `C`) per input sample,
  in input order;
- probabilities are plain floats (do not round them);
- an empty `samples.json` array must produce `{"labels": [], "probs": []}`.

## Program interface

`/app/classify.py` must be invokable with EXACTLY three positional arguments:

```
python3 /app/classify.py NETWORK SAMPLES OUTPUT
```

- `NETWORK` — path to a `network.json`;
- `SAMPLES` — path to a `samples.json` (JSON array of vectors);
- `OUTPUT` — path where the result JSON must be written.

## Constraints

- Pure Python 3 / standard library only. No packages to install, no network.
- Deterministic; do not round intermediate values.
- The verifier runs your program unchanged on the provided pair and on hidden
  pairs (varying D/H/C, an absent `standardize` key, a zero `std` entry, exact
  logit ties, huge logits, and an empty sample list), comparing labels exactly
  and probabilities to a tight tolerance.
- Do not modify or overwrite `/app/network.json` or `/app/samples.json`.

## What to deliver

1. `/app/classify.py` — the program described above.
2. `/app/predictions.json` — the output of running your program on the
   provided `/app/network.json` and `/app/samples.json`:
   ```
   python3 /app/classify.py /app/network.json /app/samples.json /app/predictions.json
   ```
