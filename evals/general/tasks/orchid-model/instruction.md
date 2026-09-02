# Orchid sensor stack — integer MLP classifier with a self-test entry

You are shipping a tiny pure-Python **integer multilayer perceptron** used by an
Orchid-series environment sensor. Three files plus one generated output must
exist under `/app` when you are done. The grader will **execute** your files
unchanged against hidden inputs (other weight sets, corrupted weight sets, other
sample files), so everything must be general — never hard-code fixture values.

## The model (fixed semantics, integer-only arithmetic)

A weight set lives in a directory containing `edge_net.json`:

```json
{
  "in_dim": 4, "hidden_dim": 6, "out_dim": 3,
  "activation": "relu",
  "W1": [[...]],   // hidden_dim rows of in_dim integers
  "b1":  [...],    // hidden_dim integers
  "W2": [[...]],   // out_dim rows of hidden_dim integers
  "b2":  [...]     // out_dim integers
}
```

`forward(net, x)` must compute, with **exact integer arithmetic only** (no
floats anywhere):

1. For each hidden unit `j`: `u_j = b1[j] + sum(W1[j][i] * x[i] for i in 0..in_dim-1)`
2. `a_j = u_j` if `u_j > 0` else `0` (ReLU)
3. For each output unit `k`: `logits[k] = b2[k] + sum(W2[k][j] * a[j] for j in 0..hidden_dim-1)`
4. `label = argmax(logits)`, ties broken toward the **lowest index**.

The return value must be a dict `{"hidden": [...], "logits": [...], "label": int}`.

## Deliverables

### 1. `/app/nn.py` — the model library

- `load_weights(weights_dir)` → dict loaded from `<weights_dir>/edge_net.json`.
- `forward(net, x)` → the dict above, per the fixed semantics, for **any**
  `in_dim`/`hidden_dim`/`out_dim` (not just the shipped 4/6/3).

### 2. `/app/selftest.py` — the self-test entry (the graded centerpiece)

An untouched self-test entry that **actually performs the checks at runtime** —
it must never fake success. Contract:

- CLI: `python3 /app/selftest.py [weights_dir]` (default `/app/weights`).
- It must **construct the model** (via `nn.load_weights`) and **perform real
  forward passes**, verifying every probe in `<weights_dir>/kat.json`:

  ```json
  {"probes": [{"x": [...], "logits": [...], "label": k}, ...]}
  ```

  For each probe: the computed `logits` must equal the expected logits
  **exactly, elementwise**, and the computed `label` must equal the expected
  `label`. It must also verify structural consistency (e.g. `len(b1) ==
  len(W1)`, every `W1` row has `in_dim` entries, every `W2` row has
  `hidden_dim` entries).
- **On success** it must print exactly one line `SELFTEST_OK` and exit `0`.
- **On any failure** it must print a line starting with `SELFTEST_FAIL:` (with a
  short reason) and exit `1`. It must not print `SELFTEST_OK` in any failure
  path, and there must be no code path that reports success without running the
  checks.
- It must expose a callable `run_selftest(weights_dir)` that performs the same
  checks and **returns** `True` on success and `False` on failure. It must
  **never raise**: a malformed-but-parseable weight set (bad JSON, missing keys,
  wrong-shaped rows, probes that mismatch) makes it return `False`.
- **No broad exception swallowing**: `selftest.py` must not contain a bare
  `except:` nor any `except BaseException` or `except Exception` handler. Catch
  specific exception types only (e.g. `json.JSONDecodeError`, `KeyError`,
  `TypeError`, `OSError`, `ValueError`). The grader enforces this by parsing
  your file, and behaviourally: corrupted weight sets must yield a failure.

### 3. `/app/predict.py` — the batch classifier CLI

```
python3 /app/predict.py <weights_dir> <samples_csv> <out_csv>
```

- `<samples_csv>`: header `x0,x1,...,x{in_dim-1}` followed by one row of
  comma-separated integers per sample.
- Writes `<out_csv>`: header line `label`, then one integer label per sample row,
  in order.

### 4. `/app/predictions.csv`

Produce it by **running your program on the shipped fixtures**:

```
python3 /app/predict.py /app/weights /app/samples.csv /app/predictions.csv
```

## Grading (hidden inputs)

- The self-test is re-run against a **fresh valid weight set** (different
  dimensions — it must still print `SELFTEST_OK`), and against **corrupted
  weight sets** (a shifted weight, a shifted bias, a missing key) where it must
  exit non-zero, print no `SELFTEST_OK`, and `run_selftest` must return `False`
  without raising.
- `predict.py` is re-run on a hidden weight set + hidden sample CSV and its
  output must match the expected labels exactly.
- `/app/predictions.csv` must equal the labels for the shipped fixtures.

## Constraints

- Python 3.12 standard library only; no network.
- Do not modify `/app/weights/`, `/app/samples.csv`, or anything under `/tests`.
- Your files must not read `/tests` or `/solution`.
