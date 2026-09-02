# Fjord Diagnostics — reconnect the sensor-fusion pipeline

You are handed a small multi-stage **sensor-fusion scorer** in `/app`. Its
training has stalled: no matter how long it trains, the loss plateaus and the
score stays mediocre. Diagnosis: **the computational graph is broken** — the
shipped `/app/pipeline.py` detaches an intermediate stage and computes the
gating stage under `no_grad`, so a backward pass never reaches every
parameter. Your job is to restore full gradient flow, retrain, and ship
auditable artifacts.

Everything runs on CPU in `/app` with `python3`, `torch` and `numpy`
(installed). Work only in `/app`; do not read `/tests` or `/solution`.

## The model

`/app/pipeline.py` defines `SensorFusionModel` with four stages:

```
encoder : Linear(d_raw -> d_ctx), tanh
context : Linear(d_ctx -> d_ctx), tanh
gate    : Linear(d_ctx -> 1),     sigmoid
head    : Linear(d_ctx -> 2)
```

Forward: `h = tanh(encoder(x))`, `c = tanh(context(h))`,
`g = sigmoid(gate(h))`, `fused = g*h + (1-g)*c`, return `head(fused)`.

**The public API must not change:**
- `class SensorFusionModel(nn.Module)` with submodules named exactly
  `encoder`, `context`, `gate`, `head`, a `.parameters()` (inherited), and
  `.forward(x) -> logits` of shape `[batch, num_classes]`;
- `build_model(meta: dict) -> SensorFusionModel` reading `d_raw`, `d_ctx`,
  `num_classes` from the meta dict.

The model must stay a plain `torch.nn` module — the fix is in the graph
topology (no detaching, no `no_grad` around trained stages), NOT in replacing
stages with hand-written analytic gradients.

## The data (per case directory)

The visible case is `/app/case/`. Each case directory contains:

- `meta.json` — `case_id`, `seed`, `d_raw`, `d_ctx`, `num_classes`,
  `train_epochs_hint`, `loss_target`, `accuracy_target`, `probe_seed`.
- `train.npz` / `test.npz` — arrays `x` (float32 `[N, d_raw]`) and `y`
  (int64 binary labels).
- `probe_batch.npz` — arrays `x`, `y`: a small fixed batch the graders use
  for the gradient-flow audit.

The class boundary is a nonlinear function that lives in the two-layer
"context" map, so a correctly connected model fits it well.

## Deliverables (all produced in `/app`)

Write ONE program, `/app/train_score.py`:

```
python3 /app/train_score.py <casedir> <outdir>     # defaults: /app/case /app
```

It must:

1. Import `/app/pipeline.py`, build the model from the case's `meta.json`
   via `build_model` (no hardcoded dimensions), and seed all RNGs from
   `meta["seed"]`.
2. Run a **gradient-flow audit**: one forward/backward pass of
   cross-entropy on the case's `probe_batch.npz`, then verify that EVERY
   named parameter has a gradient that is present (not `None`), finite, and
   non-zero (norm > 1e-8). If the audit fails, exit non-zero with a clear
   error on stderr. Record the per-parameter gradient norms.
3. Train the FULL model (all four stages) on `train.npz` — plain
   full-batch Adam, cross-entropy loss — to `final_train_loss <=
   meta["loss_target"]` (0.15) and holdout accuracy on `test.npz`
   `>= meta["accuracy_target"]` (0.88). The case metadata suggests ~1500
   epochs with a decaying learning rate works; any deterministic recipe
   reaching the targets is fine.
4. Write into `<outdir>`:
   - `model.pt` — the trained `state_dict` (exactly the model's parameter
     keys; must load into a freshly built model with `load_state_dict`).
   - `training_report.json` — JSON with keys:
     `case_id`, `seed`, `grad_norms` (object: one entry per parameter name
     with its post-audit gradient norm), `all_params_have_gradients`
     (boolean), `final_train_loss` (float), `holdout_accuracy` (float),
     `loss_target`, `accuracy_target`, `targets_met` (boolean).

Then run your program on the visible case so the artifacts appear in `/app`
itself:

```
python3 /app/train_score.py /app/case /app
```

The deliverables then exist at exactly `/app/pipeline.py`,
`/app/train_score.py`, `/app/model.pt`, `/app/training_report.json`.

## Determinism and hidden cases

- Seed every RNG from `meta["seed"]`; re-running on the same case must
  reproduce the same artifacts.
- Do not hardcode dimensions, seeds, or file contents: the graders re-run
  `/app/train_score.py` unchanged on fresh hidden cases with different
  `d_raw` / `d_ctx` / sizes / seeds and repeat the same audit: full
  gradient flow on every parameter, loaded model meeting the accuracy
  target, and a report consistent with recomputation.
- Standard library + `torch` + `numpy` only; no network at verify time.

## What must NOT be done

- Do not change the public API of `/app/pipeline.py` (names above).
- Do not detach, freeze into no-grad, or analytically patch any stage: a
  backward pass from the loss must populate a finite, non-zero gradient on
  every parameter of the composed model.
- Do not hand-author `model.pt` or the report; they must come from running
  `/app/train_score.py`.
