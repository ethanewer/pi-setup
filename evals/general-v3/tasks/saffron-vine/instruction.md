# Vineyard Ops — recover a corrupted intent classifier with a LoRA lifecycle

You are handed a small on-device **intent classifier** for vineyard sensor
voice commands. Its base checkpoint is corrupted: a failed checkpoint restore
zeroed the weight matrix of the second hidden layer (`fc2`), collapsing
holdout accuracy from ~0.93 to ~0.50 (chance). Your job is to recover the
model by running a complete **LoRA adapter train / save / reload / merge
lifecycle**, and to persist every artifact in a reloadable format.

Everything runs on CPU in `/app` with `python3`, `torch`, `numpy` and
`safetensors` (all installed). Work only in `/app`; do **not** modify anything
under `/app/case/` (read it only), and do not read `/tests` or `/solution`.

## The model and the data

`/app/case/` contains:

- `meta.json` — architecture and hyperparameters: `case_id`, `seed`,
  `vocab_size`, `embed_dim`, `hidden_dim`, `num_classes`, `seq_len`,
  `pad_id`, `lora_rank`, `lora_alpha`, `target_accuracy`,
  `lora_target_module` (always `"fc2"`).
- `base_state.pt` — a PyTorch `state_dict` of the corrupted model with
  exactly these keys:
  `emb.weight`, `fc1.weight`, `fc1.bias`, `fc2.weight`, `fc2.bias`,
  `head.weight`, `head.bias`.
  In this state `fc2.weight` is all zeros (the corruption); everything else
  is at its trained value.
- `signals.json` — recorded accuracies: `pristine_holdout_accuracy` (the
  uncorrupted model) and `degraded_holdout_accuracy` (~0.50).
- `vocab.json` — the tokenizer: mapping `token -> id` (id `0` is `<pad>`).
- `train_ids.npy` / `train_labels.npy` — training token sequences
  (`int64`, shape `[N, seq_len]`) and binary labels.
- `test_ids.npy` / `test_labels.npy` — the held-out split.

The forward pass of the model is:

```
z    = emb(ids).mean(dim=1)        # mean over the sequence dimension
t1   = tanh(fc1(z))
t2   = tanh(fc2(t1))
logits = head(t2)
prediction = argmax(logits)
```

Build the modules exactly like this (`emb` is `nn.Embedding(vocab_size,
embed_dim, padding_idx=pad_id)`; `fc1`, `fc2`, `head` are `nn.Linear`).

## Deliverables (all must be produced in `/app`)

Write ONE program, `/app/restore.py`, taking two CLI arguments consistent
with re-runs on fresh fixtures:

```
python3 /app/restore.py <casedir> <outdir>     # defaults: /app/case /app
```

It must read ALL architecture/hyperparameters from `<casedir>/meta.json`
(no hardcoded dimensions or seeds) and write, into `<outdir>`:

1. `<outdir>/adapter/adapter_weights.safetensors` — the LoRA tensors saved
   with `safetensors.torch.save_file` under the exact keys:
   - `lora_A` — shape `[lora_rank, hidden_dim]` (the down projection),
   - `lora_B` — shape `[hidden_dim, lora_rank]` (the up projection).
2. `<outdir>/adapter/adapter_config.json` — JSON with `rank`, `lora_alpha`,
   `scale` (= `lora_alpha / rank`), `target_module` (`"fc2"`), `case_id`,
   and `base_architecture` = `{vocab_size, embed_dim, hidden_dim,
   num_classes, seq_len, pad_id}`.
3. `<outdir>/adapter/feature_spec.json` — the tokenizer spec that makes the
   adapter directory self-sufficient: the token->id mapping copied from the
   case's `vocab.json` (under key `"vocab"`), plus `"seq_len"` and
   `"pad_id"`.
4. `<outdir>/adapter_merged.pt` — a full PyTorch `state_dict` of the model
   with the adapter **merged** into the base weight:
   `fc2.weight_merged = fc2.weight_base + scale * (lora_B @ lora_A)`.
   It must have exactly the same key set as `base_state.pt`, and every
   tensor other than `fc2.weight` must equal the base value exactly
   (the LoRA stage freezes the rest of the network).
5. `<outdir>/eval_metrics.json` — JSON with keys `case_id`, `seed`,
   `pristine_holdout_accuracy` (copied from `signals.json`),
   `degraded_holdout_accuracy` (recomputed by you on the test split with the
   corrupted base), `merged_holdout_accuracy` (recomputed with the merged
   model), `target_accuracy`, and `threshold_pass` (boolean,
   `merged_holdout_accuracy >= target_accuracy`).

You then run your program on the provided case so the same artifacts appear
in `/app` itself:

```
python3 /app/restore.py /app/case /app
```

After this run the deliverables exist at these exact paths:
`/app/restore.py`, `/app/adapter/adapter_config.json`,
`/app/adapter/adapter_weights.safetensors`, `/app/adapter/feature_spec.json`,
`/app/adapter_merged.pt`, and `/app/eval_metrics.json`.

## Required behavior

- Train the adapter **only** on `<casedir>/train_*` data, updating only the
  LoRA parameters (`lora_A`, `lora_B`). All base parameters
  (`emb`, `fc1`, `fc2`, `head`) stay frozen. Initialize `lora_B` to zeros
  (standard LoRA) so the adapter starts as the corrupted base.
- The adapter forward for an input batch `x` (shape `[batch, hidden_dim]`,
  the output of `tanh(fc1(z))`) is
  `x + scale * ((x @ lora_A.T) @ lora_B.T)` applied inside `fc2`, i.e.
  `t2 = tanh(fc2(t1) + scale * ((t1 @ lora_A.T) @ lora_B.T))`.
- Recovery bar: **`merged_holdout_accuracy >= target_accuracy` (0.86)** on
  the held-out split, measured with the merged model (base `fc2.weight`
  plus `scale * (lora_B @ lora_A)`). A rank-`lora_rank` adapter comfortably
  exceeds this on any well-formed case.
- Determinism: seed all RNGs from `meta.json`'s `seed` so a re-run on the
  same case reproduces the same artifacts.
- The verifier re-runs your program unchanged on fresh hidden fixtures with
  different `vocab_size` / `embed_dim` / `hidden_dim` / `seq_len` / seeds
  and checks the same artifacts, the merge equation, the reloadability of
  the adapter directory, and the accuracy bar on each. Do not hardcode
  anything case-specific.
- Standard library + `torch` + `numpy` + `safetensors` only; no network
  access at verify time.

## What must NOT be done

- Do not modify `/app/case/` (the verifier checks its integrity).
- Do not unfreeze or overwrite any base parameter: only `lora_A`/`lora_B`
  may be trained, and only `fc2.weight` may differ (by exactly the merge
  equation) in `adapter_merged.pt`.
- Do not hand-write the artifacts; they must be produced by running
  `/app/restore.py`.
