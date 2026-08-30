# Opal-Grove — author the solver and network definitions for a training run

The Opal-Grove team runs its tiny trainer, **cafelite**, from prototxt
definition files. The trainer itself is shipped and frozen; *you* must author
the **solver prototxt** and the **train/test network prototxt files** it
consumes, run the training, and ship the report it produces.

Everything happens in `/app` with Python 3.12 and `numpy`. No network.

## Provided (do NOT modify)

- `/app/cafelite.py` — the frozen trainer. It parses your solver and network
  files, builds the described MLP (zero-seeded deterministic init), trains it
  with full-batch gradient descent on CPU, and writes a JSON report. Run:
  ```
  python3 /app/cafelite.py <solver.prototxt> --train <train.csv> --test <test.csv> --report <out.json>
  ```
- `/app/data/train.csv`, `/app/data/test.csv` — datasets with header
  `x0,...,x7,label`; binary labels; 8 numeric features.

`cafelite` is strict — any rule below violated makes it exit non-zero with an
explanatory stderr message.

## Deliverables (all four required)

1. `/app/solver.prototxt`
2. `/app/train_net.prototxt`
3. `/app/test_net.prototxt`
4. `/app/run_report.json` — the report produced by running the trainer on the
   provided datasets:
   ```
   python3 /app/cafelite.py /app/solver.prototxt --train /app/data/train.csv --test /app/data/test.csv --report /app/run_report.json
   ```

## Solver file contract (`/app/solver.prototxt`)

One `key: value` per line; `#` comments and blank lines allowed. Required keys
exactly as follows:

- `solver_mode: CPU` — the run must be CPU-only; any other mode is an error.
- `max_iter: <N>` — integer with **1 <= N <= 1500**. This is the hard
  iteration cap: a value above 1500 (or below 1) is rejected. Pick `N` large
  enough to converge but never above the cap.
- `base_lr: <float>` — positive learning rate.
- `net: "<path to train network>"` and `test_net: "<path to test network>"` —
  relative paths resolve against the solver file's directory; point them at
  `/app/train_net.prototxt` and `/app/test_net.prototxt`.
- `test_interval: <int>` — integer with `1 <= test_interval <= max_iter`.

## Network file contract (`/app/train_net.prototxt`, `/app/test_net.prototxt`)

Optional `name: "..."` header, then `layer { ... }` blocks (single-line or
multi-line both parse). Required structure:

1. Exactly one `input` layer first: `type: "input"`, integer `input_dim: 8`
   (must match the datasets' feature count), and a `top`.
2. One or more `dense` layers: `type: "dense"`, integer `units` in `[1,128]`,
   `bottom` equal to the previous layer's `top`, their own `top`, and
   `activation` one of `relu`, `sigmoid`, `tanh`, `none`.
3. The final dense layer must be `units: 1` with `activation: "sigmoid"`.

The train and test networks must declare the **same** `input_dim`. They may be
otherwise identical or differ (e.g. different widths); both must satisfy every
rule above.

## Training goal

The trained model must reach, on the provided `/app/data/test.csv`:

- `final_test_accuracy >= 0.85`

Tune `base_lr`, `max_iter` (within the cap) and the hidden widths to get there.
Useful starting points: a `dense 16 / relu` hidden layer, `base_lr: 0.3`,
`max_iter: 900`. The init is seeded, so a given set of files always produces
byte-identical reports — `/app/run_report.json` must be exactly what the
trainer emits for your three prototxt files on the provided datasets.

## Report format (`/app/run_report.json`, written by cafelite)

```json
{
  "solver_mode": "CPU",
  "max_iter": 900,
  "base_lr": 0.3,
  "test_interval": 100,
  "train_rows": 400,
  "test_rows": 100,
  "input_dim": 8,
  "final_train_loss": 0.044806,
  "final_train_accuracy": 0.9875,
  "final_test_accuracy": 0.92
}
```

## What the verifier does

- Re-runs `cafelite` with **your** three prototxt files on the provided
  datasets and on **hidden** datasets (same 8-feature format, different
  distributions) and requires the reported test accuracies to clear per-case
  thresholds (0.85 on the visible test set).
- Checks your solver is `CPU`-mode, `max_iter` within `[1, 1500]`,
  `base_lr > 0`, `test_interval` in range, and that both network files parse
  and satisfy the layer contract.
- Compares a fresh trainer run against `/app/run_report.json` (floats within
  1e-4, integers exactly).

## Constraints

- Do not modify `/app/cafelite.py`, `/app/data/train.csv`, or
  `/app/data/test.csv`.
- No network access; the whole run is CPU-only and finishes in seconds.
- `max_iter` must never exceed 1500 — an uncapped run is rejected.
