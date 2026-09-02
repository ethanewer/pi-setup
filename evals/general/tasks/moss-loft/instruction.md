# moss-loft — Config-driven snapshot trainer

You must stand up a small supervised trainer that reads its architecture and
optimization plan from a JSON config, actually trains on the provided labeled
data, and leaves behind a **real trained-weights snapshot** at exactly the
configured architecture. The verifier reloads your snapshot and re-runs your
trainer end-to-end, so the artifact must be genuine, complete, and reusable.

## Working directory and fixtures

Everything runs from `/app`. The provided files are read-only — do not modify
or delete them:

- `/app/data/train.csv` — labeled training data, header
  `id,x0,...,x{input_dim-1},label` (900 rows). `label` is an integer class id
  in `[0, num_classes)`.
- `/app/data/eval.csv` — held-out evaluation data, same feature layout, with
  labels (240 rows).
- `/app/config.json` — the training plan:
  ```json
  {
    "input_dim": 8,
    "hidden_units": 24,
    "num_classes": 3,
    "epochs": 80,
    "learning_rate": 0.03,
    "batch_size": 32,
    "seed": 11
  }
  ```

## Deliverables (both required)

1. `/app/train.py` — a runnable Python trainer with this interface:
   ```
   python3 /app/train.py <train_csv> <config_json> <output_pt>
   ```
   It must work on **any** labeled CSV and config following the conventions
   below (the hidden grading cases vary `input_dim`, `hidden_units`,
   `num_classes`, `epochs`, `learning_rate`, `batch_size`, and `seed`), not
   just on the provided files.

2. `/app/model_snapshot.pt` — the weights snapshot your trainer produces when
   run as:
   ```
   python3 /app/train.py /app/data/train.csv /app/config.json /app/model_snapshot.pt
   ```

## Model architecture (fixed shape, driven by the config)

```
Linear(input_dim -> hidden_units), ReLU,
Linear(hidden_units -> hidden_units), ReLU,
Linear(hidden_units -> num_classes)
```

Prediction for a feature vector is the `argmax` of the three linear outputs.
The snapshot must contain **exactly** the six tensors of these three Linear
layers (the standard `nn.Sequential` keys are `0.weight`, `0.bias`,
`2.weight`, `2.bias`, `4.weight`, `4.bias`; a custom module layout is fine as
long as the saved mapping matches those six tensors by shape).

## Trainer requirements

- Seed all randomness from `config["seed"]` (e.g. `torch.manual_seed`) so the
  run is reproducible.
- Actually train: run the **full configured `epochs`** over the training CSV
  with an optimizer (e.g. Adam) at `config["learning_rate"]`, minibatching at
  `config["batch_size"]`. A correct run reaches high accuracy on this data —
  the verifier requires **≥ 0.85 accuracy** on held-out data drawn from the
  same distribution, so an untrained, zeroed, or dummy snapshot will fail.
- Save the trained model's state dict with `torch.save` to `output_pt`. The
  file must be a genuine, loadable torch snapshot:
  `torch.load(path, weights_only=True)` must succeed, every tensor must be
  finite, and the file must be modest in size (it holds six small tensors —
  megabyte-scale or far less).

## How it is graded

- The verifier loads `/app/model_snapshot.pt` with
  `torch.load(weights_only=True)`, checks the tensor keys and shapes match
  the architecture **configured in `/app/config.json`** exactly, checks the
  tensors are finite and non-degenerate, and scores ≥ 0.85 accuracy against
  the labels in `/app/data/eval.csv` using argmax predictions.
- The verifier then **re-executes** `/app/train.py` on several hidden
  (train CSV, config, eval CSV) cases with different dimensions, class
  counts, widths, and epoch counts, and applies the same snapshot checks
  (shape match against that case's config, real trained weights, ≥ 0.85
  accuracy against that case's eval labels) to each snapshot your trainer
  produces.

## Constraints

- CPU only, no network at verify time.
- Do not modify `/app/data/*` or `/app/config.json`.
- Do not hardcode to the visible dataset — the hidden cases genuinely differ.
- The verifier has a 300 s budget for all of its trainings; keep the trainer
  lean (the visible case trains in a few seconds).
