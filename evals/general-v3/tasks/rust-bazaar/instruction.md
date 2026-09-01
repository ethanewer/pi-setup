# Fine-tune the drifted line grader

A factory's quality grader ships as a small pretrained PyTorch snapshot. Each
new production line grades parts by a **different (independent) rule**, so the
grader must be adapted per line. Your job is to write a **reusable fine-tuning
script** and run it once on the provided line fold to leave both deliverables
in `/app`.

## Environment

- Working directory: `/app`. Read-only fixtures (you MUST NOT modify or delete
  them):
  - `/app/base_snapshot.pt` — the pretrained grader. Architecture is exactly
    `Linear(24 -> 48), ReLU, Linear(48 -> 3)` (24 features, hidden width 48,
    3 grades). The snapshot is a plain `state_dict` of these two Linear
    layers.
  - `/app/data/line_fold.csv` — the visible adaptation fold: header
    `id,x0,...,x23,label`, 600 rows, `label` in `{0,1,2}`.
- Python 3.12 with `numpy`, `pandas` and CPU-only `torch` is installed.

## Deliverables (both required)

1. `/app/finetune.py` — a runnable Python program with this interface:
   ```
   python3 /app/finetune.py <fold.csv> <out_snapshot.pt>
   ```
2. `/app/ft_visible.pt` — the adapted snapshot your program produces **when run
   on the provided visible fold**:
   ```
   python3 /app/finetune.py /app/data/line_fold.csv /app/ft_visible.pt
   ```

## What /app/finetune.py must do

- Load the base weights from `/app/base_snapshot.pt`. Parameter names inside
  the snapshot are not guaranteed — identify the two Linear layers by tensor
  shape: `(48, 24)` and `(48,)` are layer 1's weight/bias, `(3, 48)` and `(3,)`
  are layer 2's weight/bias. Any valid `state_dict` layout with exactly these
  four tensors must be accepted as base.
- Fine-tune **the whole network** on `<fold.csv>` (features `x0..x23`, target
  `label`) using an optimizer, on CPU, with a **capped schedule of strictly
  fewer than 60 epochs**.
- Write a **new** `state_dict` to `<out_snapshot.pt>`: loadable by
  `torch.load`, same four-tensor shapes as the base, and **different weights**
  from the base snapshot.
- Print one line `finetune_accuracy=<acc>` to stdout where `<acc>` is the
  trained model's classification accuracy on the fold (e.g.
  `finetune_accuracy=0.9950`).
- Be **reusable**: the script runs unchanged on folds it has never seen. Every
  fold follows the same CSV format, but each fold's labeling rule is
  independent of the base model's rule (and of the other folds'). A correct
  fine-tuner must reach **fold accuracy >= 0.90** on any such fold.

## Error handling (probed by the grader)

The script must fail gracefully — write a diagnostic to **stderr** and exit
with a **non-zero status** (never invent a snapshot) when:

- `<fold.csv>` is missing any of the required columns (`x0..x23` or `label`),
  e.g. a fold with only 23 feature columns;
- `<fold.csv>` contains a non-numeric or non-finite feature value;
- `<fold.csv>` has zero data rows (header only).

## Edge cases the verifier probes

- Hidden folds with different row counts (from ~240 to ~900 rows) and
  independent labeling rules — each must reach accuracy >= 0.90.
- A fold whose rows are ordered so the classes are interleaved arbitrarily.
- The script must not silently reuse the base weights: the produced snapshot
  must differ from `/app/base_snapshot.pt`.
- Determinism of behavior is not required, but every run must succeed and
  clear the accuracy bar.

## Constraints

- CPU only; no network access at verify time.
- Do not modify `/app/base_snapshot.pt` or `/app/data/line_fold.csv`.
- The verifier re-runs `/app/finetune.py` unchanged on hidden folds, so do not
  hard-code to the visible fold's contents.
