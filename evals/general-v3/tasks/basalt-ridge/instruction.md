# RIDGE — build a numerical workhorse for bag-attention & training logs

You are working inside a fresh CPU-only container at `/app`. Your job is to
deliver a working, *numerically robust* deep-learning component and a finished,
auditable training run. Everything runs on CPU; there is no GPU and no
prebuilt ML library available — you build the framework from numpy here.

## Context

`/app/framework.py` is the RIDGE framework: a small pure-Python autograd
library built from numpy primitives (a `Tensor` + function ops + reverse-mode
`backward`). It also provides a composed **bag-attention classifier**
(`BagModel`) and a standalone **stable-softmax primitive**
(`attention_softmax`). `/app/train.py` trains that classifier and writes a log.

**Two things in the shipped framework are wrong, and both affect the graders:**

1. `attention_softmax` is not numerically stable. It exponentiates the raw
   logits directly. For logits near magnitude `1e4` (and beyond) this
   overflows to `nan`, and it also misbehaves as magnitudes vary. The checks
   will expect **finite** weights that **sum to 1** (to the precision's
   tolerance) across extreme, tiny, single-element and variable-size inputs.
2. The model's training objective **does not converge**: no matter how long
   `train.py` runs, the loss never drops below the target (it plateaus or
   climbs). A wrong component in the objective's backward direction keeps the
   parameters moving the wrong way. Diagnose it and fix it so training
   converges.

The public API and signatures must **not change** (details below).

## What to deliver

### Deliverable A — `/app/framework.py` (repaired, self-contained)

Fix the framework so **all** of the following invariants hold for whatever
arbitrary inputs the grader feeds your module:

- **Precision & dtype correctness.** `dtype_for(name)` maps `'fp16' | 'fp32'|
   'fp64'` (and `'mixed'` → `'fp32'`). `dtype_sum_tolerance(dt)` returns
  `{'fp16':1e-1, 'fp32':1e-4, 'fp64':1e-9}`. `attention_softmax` must return
  weights **in exactly the requested dtype** whose `sum` (over the softmax
  axis) differs from `1` by at most that tolerance, with all values finite.
- **`attention_softmax(logits, axis=-1, dtype='fp32')`** returns the 2-tuple
  `(weights, logsumexp)`, both finite and in the requested dtype. Must be
  correct for logits of magnitude ~`1e4` down to ~`1e-300`, for a single
  element, and for variable-size sets along `axis`. Do **not** change the
  signature.
- **Gradient flow.** For any `BagModel`, one `forward(items)` followed by
  `backward(target)` must populate a **finite, non-zero** gradient on *every*
  parameter (`Wa`, `Wo`, `bo`). No stage may be detached.
- **Mixed precision.** A `BagModel(dtype='fp32')` fed `float16` inputs must
  still return a finite prediction in (0,1) and finite non-zero gradients.

The public surface that hidden graders call:
`framework.dtype_for`, `framework.dtype_sum_tolerance`,
`framework.attention_softmax`, `framework.stable_sigmoid`,
`framework.Tensor`, `framework.BagModel` (with `parameters()`, `forward()`,
`backward()`, `last_attention()`, `loss_value()`), `framework.backward`, and
`framework.bce_loss`.

`framework.py` must stay **CPU-only and built from numpy alone** — it must run
with no prebuilt ML framework (no torch / tensorflow / jax / caffe / sklearn).
Keep a numpy-only implementation.

### Deliverable B — `/app/train.py` (working)

`/app/train.py` already exists and is your entrypoint. It must be runnable and
must print `FINAL_LOSS=<v>`. Do not commit any change to it that breaks the
CLI. (You may adjust internal logic if needed, but keep the documented flags.)

### Deliverable C — the training run: `/app/model.pt` and `/app/train.log`

Run the training job with **this exact algorithm and these hyperparameters**
(plain full-batch SGD, plain binary cross-entropy, all defaults fixed), using
`train.py`:

```
python3 /app/train.py \
  --dims 8 --bags 24 --max-items 12 --noise 0.4 \
  --iters 500 --lr 0.05 --dtype fp32 --seed 7 \
  --target 0.02 --out /app/model.pt --log /app/train.log
```

Requirements of the run:
- The job must **converge**: the printed `FINAL_LOSS=` and the `# final_loss=`
  line in the log must be **below 0.02**. If the framework is fixed, SGD with
  these settings reaches well below 0.02.
- `/app/model.pt` must be written (a numpy npz containing `Wa`, `Wo`, `bo`,
  `dtype`, `dims`, `final_loss`).
- `/app/train.log` must record, in order: a `# config` line that echoes the
  exact hyperparameters you ran, one `epoch=<k> loss=<v>` line per epoch, a
  `# early_stop reached at epoch <k>` line when `--target` is hit (if it
  triggers), and a final `# final_loss=<v>` line.

The whole run must stay deterministic for the same `--seed`.
program and its own config so a reviewer can see exactly what algorithm ran.

## Constraints
- Work only in `/app`. Leave `/app/framework.py` implementing the API above.
- Do **not** modify anything outside your deliverables.
- You do **not** need (and must not rely on) any network, GPU, or ML library.
  numpy is already installed.
- Final state must have all four artifacts present: `framework.py`,
  `train.py`, `model.pt`, `train.log`.
- Time budget: ~12 minutes of wall-clock CPU on a single core. Keep the
  training run fast (500 epochs over 24 small bags is seconds).

## Turn-in checklist
1. `framework.py` passes the stability / precision / gradient / dtype checks.
2. The training job converges below the target and writes `model.pt` +
   `train.log` with a faithful `# config` line.
3. Everything runs on CPU, numpy-only.