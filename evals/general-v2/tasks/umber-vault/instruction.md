# umber-vault

You are given a numeric abstract dataset and must stand up a complete,
fully reproducible supervised-learning pipeline that runs entirely on CPU and
produces a concrete, re-checkable artifact set: a deterministic splitter, a
trainer that saves a real model snapshot, a reusable fine-tuner, a single-label
prediction CLI, and a streaming scorer for very large bags of patches.

## Working directory and fixtures

Everything runs from `/app`. The provided files are read-only — you MUST NOT
modify or delete them:

- `/app/data/dataset.csv` — training data, header `id,x0,x1,...,x47,label`
  (1200 rows). `label` is `0` or `1`.
- `/app/data/unlabeled.csv` — header `id,x0,...,x47` (200 rows, no label). These
  are the rows you must predict for `/app/pred_labels.txt`.
- `/app/data/finetune_fold.csv` — header `id,x0,...,x47,label` (400 rows). A
  demo fold you can fine-tune with (see below).
- `/app/data/big_bag.csv` — header `bag_id,x0,...,x47`. 6 bags, 60,000 patches
  total. Used to produce `/app/large_bag_scores.txt`.

There are **48 features** per row: columns `x0` … `x47`. Feature values are
floating-point reals. The mapping from features to labels is *not* stated in the
image; you must train a model to capture it.

## Model architecture (use it exactly everywhere)

```
Linear(48 -> 64), ReLU, Linear(64 -> 2)
```

Prediction definition for a row = `argmax` of the two logits (returns `0` or
`1`); on a tie return `0`. This is the one architecture the verifier reloads, so
do not change layers, widths, or add/remove nonlinearities, and do not add a
softmax that would change `argmax`.

No specific parameter/attribute names are required: any module layout that
saves exactly the four tensors of these two Linear layers is accepted (e.g. an
`nn.Sequential(Linear, ReLU, Linear)` whose keys are `0.*`/`2.*`, or a class
with named `l1`/`l2` modules — the verifier identifies the layers by shape).

## Deliverables you must leave in `/app`

1. `/app/split.py`
2. `/app/train.py`
3. `/app/model_snapshot.pt`
4. `/app/finetune.py`
5. `/app/predict.py`
6. `/app/pred_labels.txt`
7. `/app/large_bag_scores.txt`

### 1. `/app/split.py` — deterministic train/val/test split

Invocation:

```
python3 /app/split.py <input.csv> <out_prefix>
```

Input is any labeled CSV (header `id,x0..x47` and optionally `label`). Outputs
exactly:

- `<out_prefix>_train.csv`
- `<out_prefix>_val.csv`
- `<out_prefix>_test.csv`

Deterministic algorithm:

1. Read the CSV and sort rows ascending by the `id` column (stable sort).
2. `n = number of rows`. Build `indices = list(range(n))` and shuffle with
   `random.Random(20250531).shuffle(indices)`.
3. `ntr = round(0.7*n)`, `nval = round(0.15*n)`, `nte = n - ntr - nval`.
4. train := rows at `indices[0:ntr]`; val :=
   `indices[ntr:ntr+nval]`; test := `indices[ntr+nval:]`.
5. Write each partition to the corresponding CSV, preserving the exact input
   header row and all original columns (including `label` when it exists), rows
   in the drawn order.

The three partitions must be pairwise disjoint and together cover **every**
input id exactly once (proportions follow 70/15/15 minus whatever rounding —
that is, nothing dropped, nothing invented). Re-running the command twice on
identical input produced identical bytes.

Then produce the working splits:

```
python3 /app/split.py /app/data/dataset.csv /app/split
```

to create `/app/split_train.csv`, `/app/split_val.csv`, `/app/split_test.csv`.

### 2. `/app/train.py` — solver + network + trained snapshot

Invocation:

```
python3 /app/train.py <train.csv> <val.csv> <out_snapshot.pt>
```

- Explicit CPU-only solve: `torch.set_num_threads` is fine; the grid runs on CPU.
- The network is exactly `Linear(48->64), ReLU, Linear(64->2)`.
- Use an optimizer (SGD `lr=3e-3, momentum=0.9` preferred) with a **capped**
  iteration count: strictly fewer than 24 epochs.
- Train on the `x0..x47` features, `label` as the target, using `train.csv`;
  finish `val.csv` may be used for coarse early-stopping but is optional.
- Save a **real** weights snapshot:
  `torch.save(model.state_dict(), <out_snapshot.pt>)`.
- Print a final line like `final_train_accuracy=0.94` to stdout.

Create the deliverable with:

```
python3 /app/train.py /app/split_train.csv /app/split_val.csv /app/model_snapshot.pt
```

`/app/model_snapshot.pt` must be a non-trivial (non-dummy) trained
`state_dict`.

### 3. `/app/finetune.py` — reusable fine-tuning script

Invocation:

```
python3 /app/finetune.py <fold.csv> <out_snapshot.pt>
```

* Reads `<fold.csv>` (header `id,x0..x47,label`).
* Loads base weights from `/app/model_snapshot.pt`.
* **Fine-tunes** on `<fold.csv>` for a short capped number of epochs, same
  architecture, on CPU.
* Writes a **new** `state_dict` snapshot to `<out_snapshot.pt>`: valid, loadable,
  and changed from the base.
* Prints `finetune_accuracy=...`.

The script must adapt to a fresh fold: the fold's rule is independent, so a good
fine-tuner brings fold accuracy to `>= 0.90`.

### 4. `/app/predict.py` — single-label CLI + bag scorer

Two modes.

**(a) Label a set of rows**

```
python3 /app/predict.py <features.csv> <out_labels.txt>
```

`<features.csv>` header `id,x0..x47` (an optional `label` column is ignored).
For each row compute the class = `argmax` of the two logits. Emit exactly one
digit `0`/`1` per line to **stdout**, and write the **same bytes** to
`<out_labels.txt>` (no header, no extra text).

Create the deliverable:

```
python3 /app/predict.py /app/data/unlabeled.csv /app/pred_labels.txt
```

`/app/pred_labels.txt` is then exactly 200 lines, one digit each.

**(b) Large-bag scoring**

```
python3 /app/predict.py --bag <bag.csv> <out_scores.txt>
```

* `<bag.csv>` has header `bag_id,x0..x47`; rows of the same bag are contiguous.
* For each bag, predict the class of every patch, then the **bag score is the
  majority class** over the bag's patches; on an exact tie the score is `0`.
* Emit one score digit per bag in first-occurrence order to **stdout**, and
  write the same bytes to `<out_scores.txt>`.

* **Streaming / bounded memory is mandatory.** A bag can hold hundreds of
  thousands of patches. Read the file in chunks (e.g. `pandas.read_csv` with
  `chunksize`) and only materialize a bounded number of patch logits at a time.
  Loading the whole bag into one array/tensor or one full `read_csv` will bust
  the RAM budget. Runtime grows roughly linearly and must stay within the
  deadline.

Create the deliverable with:

```
python3 /app/predict.py --bag /app/data/big_bag.csv /app/large_bag_scores.txt
```

`/app/large_bag_scores.txt` is exactly 6 score lines.

## Edge cases the verifier probes

- Split of a **very small** labeled CSV (e.g. 7 rows) with arbitrary id
  ordering: rounding must still assign all ids exactly once, disjointly.
- A `predict.py` set with **zero rows** → empty stdout and empty output file.
- A `--bag` input with arbitrary bag counts/sizes including an **empty** bag →
  its score line simply zeros (or the bag contributes no patches; empty entire
  file → 0 lines).
- Malformed/missing feature header or non-numeric features → write an error to
  stderr and **exit non-zero** (never invent predictions).

## Constraints

- CPU only, single container, no runtime network.
- `/app/data/*` are read-only fixtures; never overwrite them.
- Leave in `/app`: the three split CSVs, the snapshot, both label/scores files,
  and the four scripts. Don't delete artifacts you created.

A correct pipeline, in order: deterministic split → trained snapshot →
fine-tuning that adapts → exact single-label predictions → streaming large-bag
scores within the memory/time budget.