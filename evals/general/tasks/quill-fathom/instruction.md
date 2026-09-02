# Adapt a frozen press classifier to unseen press folds

A print-shop runs a 3-class document-quality classifier over page-scan
features. The frozen base checkpoint was trained on one calibration run, but
each **press** (fold) drifts the class thresholds, so the base weights must be
adapted per fold by a reusable fine-tuning script. Everything runs in `/app`
on CPU. Python 3.12 with `torch`, `numpy` and `pandas` is installed.

## Provided files (read-only — do NOT modify or delete them)

- `/app/base_snapshot.pt` — frozen base checkpoint. It is a `state_dict` of
  exactly this architecture (any parameter naming is fine, the two Linear
  layers are identified by shape):

  ```
  Linear(16 -> 24), ReLU, Linear(24 -> 3)
  ```

- `/app/data/press_fold.csv` — the visible press fold: header
  `id,x0,...,x15,label` (600 rows). `label` is `0`, `1` or `2`
  (clean / minor-defect / major-defect). Features `x0..x15` are floats.

## Deliverables (both required)

1. `/app/adapt.py` — the reusable fine-tuning script, invoked as:

   ```
   python3 /app/adapt.py <fold.csv> <out_snapshot.pt>
   ```

   Contract:

   - It MUST load the base weights from `/app/base_snapshot.pt` (this exact
     path is fixed; the verifier checks the script references it and that the
     produced snapshot is derived from the same architecture).
   - It fine-tunes on `<fold.csv>` (use its `x0..x15` as features, `label` as
     the target) for a **capped** number of epochs — strictly fewer than 20 —
     on CPU, keeping the architecture exactly
     `Linear(16 -> 24), ReLU, Linear(24 -> 3)`.
   - It writes a **new**, valid, loadable `state_dict` snapshot to
     `<out_snapshot.pt>` that **differs** from the base checkpoint.
   - It prints one line `finetune_accuracy=<float>` (the fine-tuned snapshot's
     accuracy on the fold) to stdout.
   - Error handling: if `<fold.csv>` is unreadable, is missing the `label`
     column, is missing any feature column `x0..x15`, or contains zero data
     rows, it must print a diagnostic to **stderr** and exit with a non-zero
     status — and must not write an output snapshot.

2. `/app/adapted_press.pt` — the snapshot produced by running your script on
   the visible fold:

   ```
   python3 /app/adapt.py /app/data/press_fold.csv /app/adapted_press.pt
   ```

## What the verifier checks

It re-runs `/app/adapt.py` unchanged on fresh press folds it holds privately.
Those hidden folds follow the same format but differ in row count (between
roughly 300 and 750 rows), class balance, and in how the press drifts the
class rule relative to the base checkpoint. For every fold (visible and
hidden) the adapted snapshot must:

- load as a `Linear(16 -> 24), ReLU, Linear(24 -> 3)` `state_dict`,
- differ from `/app/base_snapshot.pt`,
- reach accuracy **>= 0.90** on that fold's labels.

The base checkpoint alone scores below 0.90 on the folds, so genuine
adaptation is required — simply copying or re-saving the base weights fails.
The malformed-fold error cases above are also probed.

## Constraints

- CPU only, single container, no network at verify time.
- Do not modify `/app/base_snapshot.pt` or anything under `/app/data/`.
- Keep the run fast: the whole verifier must finish within its timeout, so
  cap epochs, use a sensible batch size, and avoid unbounded loops.
