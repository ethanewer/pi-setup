# aspen-drift — Turbine-load regression with a real weight snapshot

The grid-ops team needs a CPU-only supervised regression pipeline that learns
to predict a turbine's `target` (grid load contribution, a real number) from
six sensor aggregates, and that leaves behind a **genuine trained-weights
snapshot** — not a dummy, not an oversized dump, and saved at exactly the
layer nodes the architecture prescribes.

## Working directory and fixtures

Everything runs from `/app`. The supplied files are read-only:

- `/app/data/train.csv` — header `id,x0,x1,x2,x3,x4,x5,target` (800 rows).
  The six `x*` columns are floating-point sensor aggregates in `[-3, 3]`.
- `/app/data/holdout.csv` — header `id,x0,...,x5` (200 rows, no target).
  These are the rows you must predict for `/app/predictions.txt`.

The mapping from features to target is **not** documented; you must train a
model that captures it.

## Architecture (use it exactly everywhere)

```
nn.Sequential(nn.Linear(6, 24), nn.Tanh(), nn.Linear(24, 1))
```

No other layers, no different widths, no extra nonlinearities. The snapshot
the verifier inspects must be a `state_dict` whose keys are exactly
`0.weight`, `0.bias`, `2.weight`, `2.bias` (the Sequential node numbering)
with shapes `(24, 6)`, `(24,)`, `(1, 24)`, `(1,)` — i.e. saved via
`torch.save(model.state_dict(), <path>)` on this exact module.

## Deliverables (all four required)

1. `/app/train_model.py`

   ```
   python3 /app/train_model.py <train_csv> <out_snapshot.pt>
   ```

   - Reads a labeled CSV (header `id,x0..x5,target`); train on `x0..x5`,
     target on `target`.
   - **CPU only**; use a real optimizer (Adam `lr=1e-2` or SGD with momentum)
     with a **capped** run: **strictly fewer than 30 epochs** (0 < epochs < 30).
   - Save a **real** weights snapshot with
     `torch.save(model.state_dict(), <out_snapshot.pt>)` on the exact
     architecture above. A snapshot that is all zeros, untrained, or that
     does not fit the training data will be rejected by the grader.
   - Print a final line like `final_train_mae=0.08` to stdout.
   - Error handling: if the CSV is missing, header-only (zero data rows), or
     contains a malformed/non-numeric value, print an error to stderr and
     **exit non-zero without writing the output file**.

   Create the visible deliverable with:

   ```
   python3 /app/train_model.py /app/data/train.csv /app/model.pt
   ```

2. `/app/model.pt` — the snapshot trained on `/app/data/train.csv`. The
   grader reloads it, checks the keys/shapes above, and requires the reloaded
   model to achieve **MAE ≤ 0.15 against the training targets**.

3. `/app/evaluate.py`

   ```
   python3 /app/evaluate.py <features_csv> <snapshot_pt> <out_txt>
   ```

   - `<features_csv>` has header `id,x0..x5`; an optional trailing `target`
     column **must be ignored**.
   - Loads the snapshot (`torch.load(..., map_location="cpu")`), builds the
     same architecture, loads the state dict **strictly**, and writes one
     predicted float per row to `<out_txt>` **and** prints the same lines to
     stdout.
   - Zero data rows → empty output file and empty stdout.
   - Malformed/missing input → error to stderr and exit non-zero (never
     invent predictions).

   Create the visible deliverable with:

   ```
   python3 /app/evaluate.py /app/data/holdout.csv /app/model.pt /app/predictions.txt
   ```

4. `/app/predictions.txt` — exactly 200 prediction lines (one float each).
   The grader requires **MAE ≤ 0.35** against the true targets of the
   holdout rows, so the model must generalize, not memorize.

## Edge cases the grader probes with hidden data

- Fresh training sets of different sizes (300 / 40 / 1500 rows): the trainer
  must fit them all under the same architecture, epoch cap and thresholds.
- A **header-only** train CSV → trainer exits non-zero, writes nothing.
- A train CSV with a **corrupted numeric value** → trainer exits non-zero.
- A holdout CSV that **includes a `target` column** → evaluate.py ignores it
  and still emits one prediction per row.

## Constraints

- CPU only, single container, **no network at run or verify time**.
- Never modify or delete `/app/data/*` or any other supplied file.
- Keep every deliverable in place; the verifier re-runs your scripts.
