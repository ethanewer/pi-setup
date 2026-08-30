# saffron-ember — buoy salinity classifier under sensor drift

A fleet of salinity buoys runs a small on-board classifier (16 sensor
channels, 3 water-mass classes). The fleet's deployed base model was trained
on last season's water masses; this season the water masses have **drifted**
and every calibration fold recorded this season follows the new, drifted
regime. You must leave behind a reusable fine-tuning script that adapts the
deployed base model to any such fold.

## Working directory

Everything runs from `/app`. Python 3.12 is available as `python3`. The
installed ML stack is `torch` (CPU build), `numpy` and `pandas`; use nothing
else. CPU only. Do not modify or delete any file already shipped in `/app`
(in particular `/app/base_model.pt` and `/app/data/fold_a.csv`).

## Shipped fixtures

- `/app/base_model.pt` — the deployed base model: a `state_dict` of exactly
  `Linear(16 -> 24)`, ReLU, `Linear(24 -> 3)` (four tensors; parameter names
  may be arbitrary — identify the Linear layers by shape `(24, 16)` and
  `(3, 24)`).
- `/app/data/fold_a.csv` — a calibration fold from the drifted regime,
  header `id,f0,f1,...,f15,label` (400 rows, `label` in `0..2`).

## Model architecture (use it exactly)

```
Linear(16 -> 24), ReLU, Linear(24 -> 3)
```

Keep the two Linear layers and the single ReLU; do not add or remove layers.
The verifier reloads fine-tuned snapshots by tensor shape, exactly like the
base snapshot.

## Deliverables (both required)

1. `/app/finetune.py` — a reusable fine-tuning script:
   ```
   python3 /app/finetune.py <fold.csv> <out_snapshot.pt> [--epochs N]
   ```
   - Reads the fold CSV (header `id,f0..f15,label`).
   - Loads the base weights from `/app/base_model.pt` (by shape, any
     parameter naming).
   - Fine-tunes on the fold for a short, capped schedule: default
     `--epochs` 20, and the script must refuse (exit non-zero with a stderr
     message) any `--epochs` value above 30.
   - Writes a **new** loadable `state_dict` of the same architecture to
     `<out_snapshot.pt>` whose tensors **differ from the base**.
   - Prints a final line `finetune_accuracy=<float>` (the fine-tuned
     model's accuracy on the fold it just trained on).
   - Must **not** modify `/app/base_model.pt` or the input fold.
   - Deterministic behaviour is encouraged (seed your RNG); grading does not
     depend on exact bytes, only on the accuracy threshold below.
   - Must work on **any** fold conforming to the format — the grader runs it
     on unseen drifted folds.

2. `/app/finetuned.pt` — the snapshot produced by running:
   ```
   python3 /app/finetune.py /app/data/fold_a.csv /app/finetuned.pt
   ```

## Acceptance criteria (graded by re-execution)

The grader re-runs `/app/finetune.py` on the shipped fold and on hidden
drifted folds it holds separately (different drift regimes and fold sizes —
none are the regime the base model was trained on). For every run it checks:

- the script exits 0 and prints the `finetune_accuracy=` line;
- the written snapshot loads as a valid `16 -> 24 -> 3` two-Linear
  state_dict and differs from the base;
- the fine-tuned snapshot reaches **accuracy >= 0.90** on the fold it was
  trained on (the base model scores well below that on drifted folds, so
  real adaptation is required — merely copying the base or training a dummy
  fails);
- `/app/base_model.pt` is byte-identical before and after all runs.

## Edge cases the grader probes

- A fold CSV **without a `label` column**, a fold with **zero data rows**
  (header only), or a fold containing **non-numeric** feature values: the
  script must write an error to stderr and **exit non-zero** — never invent
  a snapshot.
- The script must be reusable: two successive runs on two different folds
  must each produce their own valid snapshot.
- `--epochs 31` must be refused with a non-zero exit; `--epochs 1` must
  still run (low accuracy is fine, the run itself must succeed).

## Constraints

- CPU only, single container, no network at run time.
- Keep the fine-tuning run for a 400-row fold under ~2 minutes.
- Write outputs only to the paths given on the command line.
