# Batch-classify sensor spectra with a trained two-layer network

The materials lab's spectrometer pipeline receives a small trained MLP as a
plain-text weights bundle. You must write the batch inference program that
scores incoming spectra with it. There is no training here — the weights are
given; your job is to execute the network's forward pass exactly as specified
below and report, for every input spectrum, the softmax class distribution and
the predicted label.

## Files provided (do NOT modify them)

- `/app/network.txt` — the trained network weights bundle.
- `/app/samples.txt` — input feature vectors, one spectrum per line.

Every network/sample pair produced by the lab follows the same schema as the
provided ones. Your program must work for **any** conforming pair, not just
the provided files (the verifier runs it on additional hidden inputs).

## `network.txt` schema

Line 1:

```
ARCH <D> <R> <C>
```

- `D` = number of input features, `R` = number of hidden neurons,
  `C` = number of output classes (all positive integers).

Every subsequent non-blank line contains whitespace-separated decimal floats.
Read all of these remaining tokens **in order** (blank lines are ignored) and
slice them, row-major, into:

1. `W1` — `R * D` values: the hidden weight matrix, `R` rows of `D` entries
   each (row `i` is hidden neuron `i`).
2. `B1` — `R` values: the hidden bias vector.
3. `W2` — `C * R` values: the output weight matrix, `C` rows of `R` entries
   each (row `c` is output class `c`).
4. `B2` — `C` values: the output bias vector.

There is nothing else in the file: the total token count after the `ARCH`
line is exactly `R*D + R + C*R + C`.

## `samples.txt` schema

One input vector per line: exactly `D` whitespace-separated floats. Blank
lines are ignored (they are not vectors).

## Forward pass (execute exactly)

For each input vector `x` (length `D`):

```
h[i]    = tanh( sum_j W1[i][j] * x[j] + B1[i] )     for i in [0, R)
logit[c] = sum_i W2[c][i] * h[i] + B2[c]             for c in [0, C)
```

`tanh` is the standard hyperbolic tangent.

Then compute the softmax distribution over the logits. Use the numerically
stable form (subtract the maximum logit before exponentiating):

```
p[c] = exp(logit[c] - max_logit) / sum_k exp(logit[k] - max_logit)
```

The predicted label is the argmax of the logits; **ties are broken by the
smallest class index**.

## Output format

Write JSON to the output path with exactly two keys:

```json
{"labels": [3, 0, 1], "probs": [[0.1, 0.2, 0.3, 0.4], [ ... ], ...]}
```

- `labels` — one integer label per input vector, in input order.
- `probs` — one list of `C` floats per input vector, in input order: the
  softmax distribution `p[0..C)`.
- An empty samples file (or one containing only blank lines) must produce
  `{"labels": [], "probs": []}`.

## Program interface

`/app/classify.py` must be invokable as a CLI with EXACTLY three positional
arguments:

```
python3 /app/classify.py NETWORK SAMPLES OUTPUT
```

- `NETWORK` — path to a `network.txt` weights bundle.
- `SAMPLES` — path to a `samples.txt` file.
- `OUTPUT`  — path where the JSON result must be written.

## Determinism and constraints

- Pure Python 3 / standard library only. Do not install packages.
- No network access; deterministic; do not exec anything external.
- Do not round intermediate values. Floats are compared by the verifier with a
  small tolerance, so ordinary floating-point evaluation order differences are
  fine — but the math must be exactly the one specified (a missing `tanh`, a
  missing bias, or an un-normalized score vector will fail).
- You must NOT modify `/app/network.txt` or `/app/samples.txt`.

## What to deliver

1. `/app/classify.py` — the program described above (your main deliverable).
2. `/app/predictions.json` — the output of running your program on the
   provided visible fixtures:
   ```
   python3 /app/classify.py /app/network.txt /app/samples.txt /app/predictions.json
   ```

The verifier will:
1. run your program on the provided network/samples and compare against the
   expected labels and probabilities,
2. run your program on hidden network/sample pairs with different
   `D`/`R`/`C` (including an empty samples file and a network whose output
   logits tie exactly — the label must then be the smallest class index) and
   check the exact predictions.
