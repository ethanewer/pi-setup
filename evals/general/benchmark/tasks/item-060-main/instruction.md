# Infer, Freeze, Fine-Tune a Mini Transformer

The container holds:

- `/app/models/base_state.pt` — a PyTorch **state dict** of a trained-looking
  `MiniTransformer` (see `/app/model.py` for the architecture family:
  token embedding, positional parameter, `n_layers` transformer blocks each
  containing LayerNorm + multi-head self-attention + MLP, a final LayerNorm,
  mean-pooling, and a linear `head`). The exact hyperparameters
  (`vocab_size`, `max_len`, `d_model`, `n_heads`, `n_layers`, `num_classes`)
  are **hidden**: you must re-derive them from the tensor shapes in the
  serialized state dict alone.
- `/app/train.py` — a fine-tuning pipeline with two functions left for you to
  implement (`infer_config`, `freeze_policy`); the training loop, evaluation,
  checkpointing and reporting are already written.
- `/app/dataset.py` — deterministic synthetic data (`class = sum(seq) mod
  num_classes`).

## Your Task

Run the fine-tuning pipeline end-to-end and leave its artifacts on disk.

1. **Infer the architecture from the evidence.** Implement `infer_config` in
   `/app/train.py` so that the returned `TConfig` reproduces **exactly** the
   shape of every tensor in the state dict. Your inference is correct when
   `model.load_state_dict(state, strict=True)` succeeds without missing or
   unexpected keys. The state dict itself tells you everything:
   - `token_emb.weight` → `(vocab_size, d_model)`
   - `pos_emb` → `(1, max_len, d_model)`
   - `blocks.<i>.attn.head_scale` → `(n_heads,)` (one scalar per attention head)
   - the set of block indices in `blocks.<i>.*` keys → `n_layers`
   - `head.weight` → `(num_classes, d_model)`
   Verify by loading; if `load_state_dict` complains, adjust your inference.

2. **Freeze exactly the requested parameters.** Implement `freeze_policy` in
   `/app/train.py`) so that the **only** trainable parameters of the model are
   those of the prediction head (parameter names starting with `head.`, i.e.
   `head.weight` and `head.bias`). Every other parameter (embeddings, blocks,
   norms) must have `requires_grad = False`. Return
   `(trainable_param_count, frozen_param_count)` — pass `["head."]` as the
   allowed-prefix list from `main`.

3. **Check training and evaluation behavior.** Run `/app/train.py`. It trains
   for 300 Adam steps on the synthetic split, evaluates held-out accuracy,
   saves `/app/output/finetuned.pt` and writes `/app/output/report.json`
   containing `config`, `trainable_params`, `frozen_params`, `val_accuracy`,
   and `steps`. Confirm the numbers in the report make sense: the head of this
   Transformer has `num_classes * d_model + num_classes` trainable elements;
   the frozen count must equal total parameter elements minus that; and
   `val_accuracy` must be a float in `[0, 1]`.

## Constraints and tips

- Do not change the architecture: `build_model(cfg)` with your inferred cfg
  must reproduce the state dict's keys and shapes one-to-one.
- Do not copy `/app/models/base_state.pt` to `/app/output/finetuned.pt` as a
  shortcut: the checkpoint must reflect actual training of the head.
- The optimizer must see **only trainable** parameters — since `freeze_policy`
  runs before `train` builds its optimizer, freezing correctly is enough.
- Deterministic everything (seeds are fixed), so your results will be
  reproducible.

## Success criteria

A verifier will: load `/app/output/finetuned.pt` and check its keys/shapes
match the true architecture; compare it against a pristine copy of the base
checkpoint — every non-head parameter must be bit-identical (frozen) while
`head.weight`/`head.bias` must have actually changed (trained); and validate
that `/app/output/report.json` reports the correct config, the correct
trainable count (only the head), and a float `val_accuracy` in `[0, 1]`.