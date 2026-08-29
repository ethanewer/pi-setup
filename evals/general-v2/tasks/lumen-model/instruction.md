# Quantized model inference

You must write a self-contained Python program `/app/infer.py` that runs
inference on a small quantized neural network described by two JSON files.

## Files provided (do NOT modify them)

- `/app/model.json` — network topology as integers, plus a per-tensor
  quantization `scale` and zero point `zero`.
- `/app/vectors.json` — a JSON array of feature vectors to classify, in order.

Every model produced by the contract uses the same schema as the provided
one. Your program must work for ANY model/vector file following this schema,
not just the provided ones (the verifier runs it on additional hidden inputs).

## model.json schema

```json
{
  "w1": [[...], [...], ...],   // hidden weight matrix, shape [R, D]
  "b1": [ ... ],               // hidden bias, length R
  "w2": [[...], [...], ...],   // output weight matrix, shape [C, R]
  "b2": [ ... ],               // output bias, length C
  "scale": 2,
  "zero": -3
}
```

- `R` = number of hidden neurons, `D` = number of input features,
  `C` = number of output classes.
- `w1` has `R` rows; each row has exactly `D` entries (D > 0).
- `b1` has exactly `R` entries.
- `w2` has `C` rows (C > 0); each row has exactly `R` entries.
- `b2` has exactly `C` entries.
- `scale` and `zero` are numbers (may be 0, may be fractional).

## Dequantization (the critical step)

Every entry stored in `w1`, `b1`, `w2`, `b2` is an integer "quantized" value.
You must dequantize each of them:

```
real = scale * (quantized - zero)
```

Apply this to weights AND biases before doing arithmetic. Do not skip it, and
do not apply it twice. The hidden cases use non-trivial `scale`/`zero`
(sometimes `scale` and `zero` are not both "identity"), so a naive pass that
ignores the dequant step will produce wrong labels.

## Forward pass

Associate the dequantized tensors as `W1, B1, W2, B2`.

For each input feature vector `x` (length `D`):

```
h[i] = ReLU( sum_j W1[i][j] * x[j] + B1[i] )     for i in [0, R)
logit[c] = sum_i W2[c][i] * h[i] + B2[c]           for c in [0, C)
label[x] = argmax(logit), with ties broken by the smallest index c
```

`ReLU(v) = max(0, v)`. Labels are 0-based class indices.

## Output format

Write JSON to the output path:

```json
{"labels": [0, 1, ...]}
```

one integer label per input vector, in the same order. Use JSON, not a custom
format. An empty input list must produce `{"labels": []}`.

## Program interface

`/app/infer.py` must be invokable as a CLI with EXACTLY three positional
arguments:

```
python3 /app/infer.py MODEL VECTORS OUTPUT
```

- `MODEL` — path to a `model.json`.
- `VECTORS` — path to a `vectors.json` (JSON array of feature vectors).
- `OUTPUT` — path where the result `labels.json` object must be written.

## Error handling (hidden cases probe these)

Your program MUST reject malformed or inconsistent input rather than silently
guessing. On any of the following it must exit with a NON-zero status, print a
helpful message to stderr, and NOT write the output file:

- a specified file is missing or not valid JSON;
- any required key (`w1`, `b1`, `w2`, `b2`, `scale`, `zero`) is missing;
- `w1` has ragged rows (rows of different lengths) or is empty;
- `b1`/`w2`/`b2` have the wrong lengths for the stated shapes;
- any input feature vector's length != D (the width of `w1`);
- non-numeric entries anywhere.

Ties in the output argmax (two classes with equal top logit) are valid input
and must be broken by choosing the smallest class index — never by raising an
error.

## Determinism and constraints

- Pure Python 3 / standard library only. Do not install packages.
- Deterministic and self-contained: no network, no exec of anything external.
- Floating-point differences from the true value are permitted only if the
  argmax class does not change. Do not round intermediate values.
- You must NOT modify or overwrite `/app/model.json` or `/app/vectors.json`.

## What to deliver

Write `/app/infer.py` (your single deliverable). The verifier will:
1. run the provided model/vectors case and compare against the expected labels,
2. run your program on multiple fresh hidden models/vectors and check the
   exact predicted labels,
3. feed malformed/modeled mismatched inputs and require a failing exit.