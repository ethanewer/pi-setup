# Deep Transformer Surgery: Infer, Freeze Precisely, Fine-Tune

The container holds:

- `/app/models/base_state.pt` — a PyTorch **state dict** of a `MiniTransformer`
  (architecture is in `/app/model.py`). This network is **deeper** than a toy:
  it is a mixture of token embedding, positional parameter, **multiple**
  transformer blocks (each: LayerNorm + multi-head self-attention + MLP), a
  final LayerNorm, mean-pooling, and a linear `head`. The hyperparameters
  (`vocab_size`, `max_len`, `d_model`, `n_heads`, **`n_layers`**,
  `num_classes`) are **hidden** and must be re-derived from the tensor shapes
  in the serialized state dict alone.
- `/app/train.py` — a fine-tuning pipeline with two functions for you to
  implement (`infer_config`, `freeze_policy`). The training loop, evaluation,
  checkpointing, and reporting are already written.
- `/app/dataset.py` — deterministic synthetic data (`class = sum(seq) mod
  num_classes`).

## Your Task

Run the fine-tuning pipeline end to end and leave its artifacts on disk.

1. **Infer the architecture from evidence.** Implement `infer_config` so the
   returned `TConfig` reproduces **exactly** every tensor's shape in the state
   dict, including the true **`n_layers`** (there are more than two blocks in
   this variant). Validate by loading: `model.load_state_dict(state,
   strict=True)` must succeed with no missing or unexpected keys. Derive from:
   - `token_emb.weight` → `(vocab_size, d_model)`
   - `pos_emb` → `(1, max_len, d_model)`
   - `blocks.<i>.attn.head_scale` → `(n_heads,)`
   - the set of block indices `i` appearing in `blocks.<i>.*` keys → `n_layers`
   - `head.weight` → `(num_classes, d_model)`
   Confirm `n_layers` by counting the distinct block indices; be exact.

2. **Freeze exactly the requested parameters.** The requested trainable set is
   narrow and precise: **only the parameters of the LAST transformer block and
   the prediction head** are trainable. All of the following must have
   `requires_grad = False`:
   - `token_emb.weight`, `pos_emb`,
   - every `blocks.0.*` and `blocks.1.*` parameter (all earlier blocks entirely),
   - the final LayerNorm parameters (`final_norm.*`).
   Only `blocks.<last>.*` and `head.*` stay trainable. Implement
   `freeze_policy` so it takes the allowed-prefix list `["blocks.<last>.", "head."]`
   (the skeleton's `main` already computes `<last>` = `n_layers-1`) and returns
   `(trainable_param_count, frozen_param_count)`.

3. **Check training and evaluation behavior.** Run `/app/train.py`. It trains
   400 Adam steps on the synthetic split, evaluates held-out accuracy, saves
   `/app/output/finetuned.pt` and writes `/app/output/report.json` containing
   `config`, `trainable_prefixes`, `trainable_params`, `frozen_params`,
   `val_accuracy`, and `steps`. Sanity-check the report: the sum of reported
   trainable + frozen elements must equal the model's total parameter count,
   and `trainable_params` must equal exactly the element count of
   `blocks.<last>.*` plus `head.*`.

## Adversarial notes (read carefully)

- The verifier keeps a pristine copy of the base checkpoint. To score full
  credit it will confirm that **every** frozen parameter (including all of
  `blocks.0`,`blocks.1`, `token_emb`, `pos_emb`, `final_norm`) is
  **bit-identical** between the base and your saved checkpoint, while **every**
  trainable parameter (`blocks.<last>.*` and `head.*`) has **actually changed**
  from base — i.e. you trained them, and only them.
- Do **not** just copy `base_state.pt` to the output: then nothing changes.
- If you silently freeze the wrong subset (e.g. freeze everything, or freeze
  too little), the verifier's bit-identity check will fail.

## Success criteria

The verifier will: reconstruct the true architecture and load
`/app/output/finetuned.pt` against it (keys + shapes must match exactly);
compare it to the pristine base — all non-`(blocks.<last>|head).*` parameters
bit-identical, all of `blocks.<last>.*` and `head.*` changed; and validate
`/app/output/report.json` (true config, exact trainable count for the
last-block-plus-head policy, correct total accounting, `val_accuracy` a float
in `[0,1]`).