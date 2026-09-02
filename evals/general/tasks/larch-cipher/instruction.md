# larch-cipher — fix a stalled CPU classifier, fine-tune its head, run a small
# LoRA lifecycle, persist everything, and evaluate it deterministically

## Goal

Inside `/app` there is a small two-class CPU classifier that underperforms. Your
job is to write ONE program, `/app/finetune.py`, that:

1. Diagnoses why the classifier is stalled using its recorded training signals
   and the model definition.
2. Applies a single corrective change and fine-tunes ONLY the designated output
   layer (head), leaving every other parameter at its original value.
3. Runs a small LoRA adapter train / save / merge lifecycle.
4. Persists every trained model / result array in loadable file formats.
5. Evaluates the final merged model deterministically under a fixed random seed.

You then run `/app/finetune.py` yourself to produce your deliverables in `/app`.

## Provided data and model

Everything you need to start is under `/app/case/`:

- `meta.json` — model architecture: `input_dim`, `hidden_dim`, `out_dim`,
  `case_id`, `seed`, `target_accuracy`, and helper hints.
- `base_state.pt` — a PyTorch `state_dict` of the under-performing model.
  Architecturally it is a small MLP:
  `fc1` (input_dim -> hidden_dim, ReLU) -> `fc2` (hidden_dim -> hidden_dim,
  ReLU) -> `head` (hidden_dim -> out_dim). `head` is the **designated output
  layer**.
- `training_signals.json` — the recorded training/validation signals from the
  run that produced this low-accuracy state: per-epoch train loss, val
  accuracy, and the **head's gradient norm**.
- `X_train.npy`, `y_train.npy` — training features (float32, 2-D) and labels
  (int64, 0/1).
- `X_test.npy`, `y_test.npy` — held-out evaluation features and labels.

The features are rows of real numbers; labels are binary. The dataset is
balanced. `out_dim == 2`, so the head emits logits over the two classes and the
predicted class is `argmax` of the logits.

### Why it stalls (diagnostic signal)

The recorded `training_signals.json` are the key clue: every epoch the train
loss stays flat at about `ln(2) ≈ 0.693`, the head gradient norm is `0.0`, and
the validation accuracy is stuck at chance (`≈0.5`) no matter how long it is
trained. Inspect the model too. Identify the specific defect in the base state
that prevents the optimizer from ever improving the output layer, then make the
**minimal single change** that lets training converge.

Your deliverable program must reproduce this reasoning in code (e.g. by
logging the base accuracy and confirming the head defect) before fixing it.

## Deliverables (all must be produced in `/app`)

Your program writes, at the exact paths below:

1. `/app/head.pt` — full PyTorch `state_dict` of the FINE-TUNED model. It must
   differ from `base_state.pt` **only in the `head.*` parameters**; `fc1.*` and
   `fc2.*` must equal the base values exactly (they stay frozen).
2. `/app/adapter_merged.pt` — full PyTorch `state_dict` of the model with the
   LoRA adapter **merged** into the base weight of `fc2` (i.e.
   `fc2.weight = base_fc2.weight + scale * (B @ A)`). All other parameters,
   including the fine-tuned `head.*`, unchanged. Keys must be exactly the same
   set as `base_state.pt`.
3. `/app/state_dict.pkl` — the same final model, persisted with Python
   `pickle` as a plain **state-dict** (`dict` of tensors with the canonical
   keys above), loadable via `pickle.load`.
4. `/app/eval_metrics.json` — deterministic evaluation results:
   - `case_id`, `seed`, `n_trials`,
   - `"mean_reward"`: the mean accuracy of the merged model over a fixed-seed
     reward-collection loop on the held-out pool,
   - `"eval_accuracy_head"` and `"eval_accuracy_merged"`.
5. `/app/embeddings.npy` — a NumPy array saved with `np.save` (loadable with
   `np.load`), containing the output-layer weight tensor (the "target array"
   used by the persisted state dict).
6. `/app/classifier.pkl` — a fitted, pickled **scikit-learn** predictor (an
   estimator with a `.predict` method, e.g. `LogisticRegression`) trained on
   the raw `X_train`/`y_train` inputs and loadable via `pickle.load`.
7. `/app/lora_adapter/` — directory containing, at the exact paths
   `/app/lora_adapter/adapter_weights.safetensors` and
   `/app/lora_adapter/adapter_config.json`:
   - `/app/lora_adapter/adapter_weights.safetensors` — the LoRA `A` and `B`
     tensors (save with `safetensors`; load under keys `lora_A`, `lora_B`),
     and
   - `/app/lora_adapter/adapter_config.json` — JSON with `rank`,
     `lora_alpha`, `scale` (`= lora_alpha / rank`), `target_module`, and the
     base architecture.
   The directory must be self-sufficient: from it + the base state_dict an
   evaluator can reconstruct the exact merged model.

Required accuracy (evaluated on the held-out test partition, in `/app`):
- `head` fine-tune accuracy **>= 0.85**,
- merged-LoRA accuracy **>= 0.84**,
- deterministic seeded `mean_reward` **>= 0.82**.

The stalled base (before your fix) is far below these (~chance).

## Determinism policy and the "reward" evaluation

Compute the held-out accuracy through a fixed-seed reward loop so it is fully
reproducible: seed the RNG, draw the set of held-out trials, and accumulate
`+1` per correct prediction, reporting `mean_reward`. Because the merged model
is deterministic in eval mode (no dropout), running the same evaluation twice
with the same seed must give **exactly** the same number. `eval_metrics.json`
should reflect this determinism.

## Must-follow rules

- Write `/app/finetune.py`. Make it a single self-contained program taking two
  CLI arguments consistent with re-runs:
  `python3 /app/finetune.py <casedir> <outdir>`
  with defaults `<casedir>=/app/case`, `<outdir>=/app`. It must:
  - **read the architecture from `meta.json`** (do NOT hardcode the dimensions)
    so the SAME program works on other mini-datasets with different
    `input_dim`/`hidden_dim`/(seeds); the verifier will re-run your program on
    fresh hidden datasets and check the same artifacts.
  - parse its arguments and write the deliverables into `<outdir>`.
- Freeze `fc1` and `fc2`; only `head.*` may be updated during the head
  fine-tune (the frozen exact-match is checked against the base).
- For the LoRA step, freeze the whole fine-tuned network; only the low-rank `A`
  (and optionally `B`) parameters are trained; then **merge** the adapter into
  `fc2.__weight__` and save the merged state dict. The unmerged base `fc2`
  must not be altered in the merged file (the merge is a separate, verifiable
  addition).
- Do not modify `/app/case/` contents; read them only.
- Everything must run on a single CPU container with plain `python3`, `torch`,
  `numpy`, `safetensors`, `scikit-learn` (already installed).

## What must NOT be done

- Do not read `/tests`, `/tests/hidden`, or `/logs`; you only see `/app`.
- Do not hardcode any particular case's seed/numbers into `finetune.py`.
- Do not replace the required artifacts with stray files; every artifact must
  load at exactly the path above.

When finished, run:

```
cd /app
python3 /app/finetune.py /app/case /app
```

and confirm all the listed files exist in `/app`. That completes the task.