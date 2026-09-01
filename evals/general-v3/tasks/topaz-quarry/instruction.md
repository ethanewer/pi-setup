# Train the sensor-array fault classifier and save a real weights snapshot

The fault-detection team trains a small linear classifier that maps a sensor
array reading to one of several fault classes. Your job is to write the
training program, run it on the provided data, and leave behind a **real
trained weights snapshot** that the deployment verifier can reload into the
exact architecture below.

## Files provided (do NOT modify them)

- `/app/data/train.csv` — training data, header `id,f0,...,f9,label`
  (900 rows, labels `0..2`).
- `/app/data/eval.csv` — held-out evaluation data, same header, including a
  `label` column (200 rows).
- `/app/data/config.json` — the run configuration:
  ```json
  {"input_dim": 10, "classes": 3, "max_epochs": 120,
   "arch": "linear_fc", "snapshot_keys": ["fc.weight", "fc.bias"]}
  ```

Every run follows the same schema. Your trainer must work for **any** conforming
train/config pair, not just the provided ones — the verifier runs it on hidden
runs with a different `input_dim` and class count (and correspondingly shaped
CSV files).

## Architecture (exactly this, everywhere)

```python
class Net(torch.nn.Module):
    def __init__(self, input_dim, classes):
        super().__init__()
        self.fc = torch.nn.Linear(input_dim, classes)
    def forward(self, x):
        return self.fc(x)
```

The trained model's `state_dict` therefore has EXACTLY the two keys
`fc.weight` (shape `[classes, input_dim]`) and `fc.bias` (shape `[classes]`).
No extra layers, no extra keys, no missing keys.

## Deliverables (both required)

1. **`/app/train.py`** — invokable as:

   ```
   python3 /app/train.py <train_csv> <config_json> <out_pt>
   ```

   - Read `input_dim` and `classes` from `<config_json>` (use them for the
     architecture; the CSV header must agree).
   - Train on all rows of `<train_csv>`: features `f0..f{input_dim-1}`,
     target `label`.
   - The epoch budget is **capped** by `max_epochs` from the config: the
     training loop must run at most that many epochs.
   - At the end, save a **real weights snapshot**:
     `torch.save(model.state_dict(), <out_pt>)` — the state_dict of the
     trained `Net`, nothing else (not the whole module object).

2. **`/app/model.pt`** — the snapshot for the visible run:

   ```
   python3 /app/train.py /app/data/train.csv /app/data/config.json /app/model.pt
   ```

## Snapshot quality bar

The deployment verifier reloads each snapshot with `strict=True` into a fresh
`Net` and checks:

- the file loads via `torch.load(..., map_location="cpu")` into a plain dict
  with exactly the keys `fc.weight` and `fc.bias`, correct shapes, all values
  finite;
- the weights are genuinely trained — not a dummy: the weight tensor is not
  all zeros/constant;
- and, decisively, the reloaded model's `argmax` predictions on the matching
  held-out eval CSV reach **accuracy >= 0.90** against the `label` column.

Important: the verifier feeds **raw feature values** through the reloaded
model — any normalization must either be left out or baked into the saved
weights themselves. A recipe known to clear the bar comfortably on this data
family: train directly on the raw feature values with SGD
(`lr=0.1, momentum=0.9`) on cross-entropy, using the full `max_epochs`
budget. The classes are linearly separable, so a converged linear model
scores far above 0.90 — but an underfit run (too few effective steps, or a
too-small learning rate) will not.

## Edge cases the verifier probes

- A hidden run with a different `input_dim`, class count, and row count —
  your trainer must size everything from `<config_json>` and the CSV header,
  never from the visible files.
- Snapshots that are dummies (all-zero or constant weights), oversized
  (extra layers/keys), or wrong-shaped must all fail the reload check.

## Constraints

- CPU only. `torch` (and `numpy`) are preinstalled; do not install packages.
- Deterministic seeds are recommended but the verifier does not require a
  bit-exact snapshot — only that it reloads and performs.
- No network access; do not modify anything under `/app/data`.
