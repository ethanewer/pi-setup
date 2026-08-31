# tide-grove — Iteration-capped checkpoint trainer

You must build a small, fully deterministic supervised-training script that
reads a labeled CSV and a config file, trains a fixed MLP for **exactly** the
configured number of full-batch iterations, and saves a **real weights
snapshot** under a checkpoint directory whose node name records the iteration
count. The grader re-runs your script on hidden datasets and configs, so
everything must be driven by the inputs, never hard-coded.

## Environment

Working directory: `/app`. Python 3.12 is available as `python3`. The image
provides:

- `/app/data/train.csv` — labeled training data, header
  `id,x0,...,x15,label` (400 rows; `label` is `0` or `1`, features are floats).
- `/app/data/holdout.csv` — same schema, drawn from the same rule; the grader
  uses it to check that your snapshot actually learned the rule.
- `/app/train_config.txt` — the visible training configuration.

Do **not** modify or delete anything under `/app/data/` or
`/app/train_config.txt`.

## Deliverables

1. `/app/train.py` — the trainer (contract below).
2. `/app/checkpoints/iter-120/model.pt` — the trained snapshot your script
   produces for the visible config, i.e. the result of:

   ```
   python3 /app/train.py /app/data/train.csv /app/train_config.txt /app/checkpoints
   ```

   (In general the snapshot for a config with `iterations = N` must be written
   to `<ckpt_root>/iter-<N>/model.pt`, so the full deliverable pattern is
   `/app/checkpoints/*/model.pt`.)

## Config file format

`train_config.txt` (and every hidden config) is plain text with `key = value`
lines; blank lines and lines starting with `#` may appear:

```
iterations = 120   # full-batch optimizer steps (positive int)
hidden     = 24    # hidden layer width
lr         = 0.08  # SGD learning rate (float)
seed       = 7     # RNG seed for weight initialization
```

## `/app/train.py` contract

```
python3 /app/train.py <train_csv> <config_file> <ckpt_root>
```

1. Parse the config file into `iterations`, `hidden`, `lr`, `seed`.
2. Read the CSV: header `id,x0,...,x{d-1},label`. Infer the feature dimension
   `d` from the header (do not assume 16). Features are the `x*` columns,
   target is `label`.
3. Build the network **exactly**:
   `Linear(d, hidden)` → `ReLU` → `Linear(hidden, 2)`.
4. Seed weight initialization with `torch.manual_seed(seed)`.
5. Train full-batch with `SGD(model.parameters(), lr=lr, momentum=0.9)` and
   `CrossEntropyLoss` for **exactly `iterations` optimizer steps** on the whole
   training set (float32, CPU).
6. Create `<ckpt_root>/iter-<iterations>/` and save the trained weights there
   as a plain `state_dict`:
   `torch.save(model.state_dict(), "<ckpt_root>/iter-<iterations>/model.pt")`.
7. Also write `<ckpt_root>/iter-<iterations>/meta.json` with exactly:
   `{"iterations": <int>, "hidden": <int>, "lr": <float>, "seed": <int>,
     "feature_dim": <int>}`.
8. Print a final line `final_accuracy=<float>` (training accuracy of the
   snapshot on `<train_csv>`).

The script must be **deterministic**: run twice with the same inputs, it must
produce identical snapshots (the same tensors, tensor-for-tensor).

## What the grader checks (visible and hidden cases)

- The snapshot exists at `<ckpt_root>/iter-<N>/model.pt` with `N` taken from
  the case's config (hidden cases use **different** iteration counts, hidden
  widths, learning rates, seeds, and feature dimensions — e.g. a 10-dim, a
  24-dim and a 6-dim dataset — so nothing may be hard-coded).
- `meta.json` matches the config and the CSV header.
- The snapshot is a **real trained state_dict**: loadable with
  `torch.load(..., weights_only=True)`, exactly the four tensors of the two
  Linear layers (identified by shape: `(hidden, d)`, `(hidden,)`, `(2, hidden)`,
  `(2,)`), all finite, non-degenerate (non-constant rows), reasonably sized
  (not a dummy blob, not an oversized checkpoint).
- It actually **learned the rule**: rebuilt as
  `Linear(d, hidden) → ReLU → Linear(hidden, 2)` and loaded with your tensors,
  it must reach accuracy `>= 0.85` on the case's holdout CSV (the visible
  `/app/data/holdout.csv` for the visible case) and `>= 0.85` on its train CSV.
- **Determinism**: the grader runs your `train.py` twice on each case into two
  fresh checkpoint roots; both snapshots must be tensor-for-tensor equal, and
  equal to the delivered `/app/checkpoints/iter-120/model.pt` on the visible
  case.
- The printed `final_accuracy` on each case must be `>= 0.85`.

## Constraints

- CPU only; no network at grading time; standard library + the preinstalled
  `torch` are sufficient.
- Training on the full training set in memory is fine (datasets are small).
- Keep the snapshot small (a few KB — it is only ever `2·hidden·(d+1)` +
  `2·(hidden+1)` floats).
