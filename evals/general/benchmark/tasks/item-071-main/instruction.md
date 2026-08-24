# Item-071 (medium) — Distributed pipeline-parallel training of a tiny LLaMA model

You are an ML systems engineer. Your team is porting a small LLaMA-style
language model to a **2-process pipeline-parallel** training harness with
microbatching under an **AFAB (all-forward / all-backward) schedule**. A
canonical single-process reference defines the exact semantics your parallel
engine must reproduce: same forward, same loss, same gradients, same final
parameters. Your engine must be genuinely **distributed** (two processes, one
per pipeline stage, exchanging activations over
`torch.distributed`), must run to completion, and must leave on disk the
weights + a validation report that prove forward/backward equivalence with the
reference.

## Container contents

- `/app/reference.py` — canonical reference implementation. **Read-only
  contract**: you must NOT modify it. It is the single source of truth for the
  model definition, loss, gradients, and SGD updates. Read it carefully.
- `/app/data/tokens.pt` — deterministic synthetic corpus:
  `torch.load` → int64 tensor shape `(5, 4, 16)` = `[step, batch, seq_len]`,
  token indices in `[0, 64)`.
- `torch` (CPU) and `numpy` preinstalled; `torch.distributed` with the gloo
  backend is available (no GPU needed).

## Model + training contract (identical to the reference)

- `vocab=64`, `d_model=32`, `n_heads=8`, `head_dim=4`, hidden width `64`,
  **6 decoder blocks**, final RMSNorm + LM-head projection; forward/loss
  exactly as in `reference.forward` / `reference.loss`.
- Cross-entropy loss is the mean over `(batch × (seq_len-1))` next-token
  predictions (see `reference.loss`).
- **Parameters** (names are the keys of `reference.build_params()`):
  - `stage0` owns: `embed`, and every `blocks.{0,1,2}.*`
  - `stage1` owns: every `blocks.{3,4,5}.*`, `head.ln`, `head.out`
- **Initialization**: every rank builds its own shards from
  `reference.build_params(seed=20260407)` — deterministic; do not use any
  other seed or a different init scheme.
- **Optimizer**: plain SGD, `lr = 0.05`, applied per parameter:
  `w ← w - 0.05 * g`, where `g` is the **mean of the per-microbatch gradients**
  (`g = (1/M) Σ_m ∂loss_m/∂w`). No weight decay, no momentum, no clipping.
- **Data per step**: global step `s` uses `tokens.pt[s]` → shape `(4, 16)`.
  Microbatch 0 = rows `[0:2]`, microbatch 1 = rows `[2:4]`.
  Train **4 steps** (steps 0..3; row 4 of the corpus is unused by this
  flavor).

## AFAB schedule (implement exactly this ordering)

For each global step:

1. **Forward phase** — for micro `m` in `0, 1 (in order)`:
   - stage0 embeds its micro-tokens and runs its layers → hidden `h_m`
     (shape `(2,16,32)`), detaches at the stage boundary and sends `h_m` to
     stage1 (point-to-point).
   - stage1 receives `h_m`, runs its layers + head, computes
     `loss_m` (the mean CE over its microbatch rows).
2. **Backward phase** — for micro `m` in `0, 1 (in order)`:
   - stage1 backprops `loss_m` locally and obtains
     `dh_m = ∂loss_m/∂h_m` (the gradient of the hidden it received); it
     accumulates its own parameter gradients and sends `dh_m` to stage0.
   - stage0 receives `dh_m` and runs
     `torch.autograd.backward(h_m_local, dh_m)` so its `embed`/layer
     gradients accumulate for that microbatch.
3. **Synchronize**: both stages must `torch.distributed.barrier()` before
   proceeding (no rank may race ahead).
4. **Update**: each stage averages its accumulated gradients over the M
   microbatches and applies the SGD rule to its OWN parameters only.

You are responsible for pairing the sends/recvs correctly (including tensors
needed by the backward phase; `h_m` from the forward pass of the same
microbatch must be the graph the backward hooks into). The schedule must not
deadlock and must be reproducible.

## Implementation contract

Create `/app/engine/` containing at least:

- `main.py` — the distributed entrypoint. Initialize the process group with
  `gloo`, `torch.set_num_threads(1)`, build the canonical init, run the AFAB
  loop above, save the outputs. It must work when launched with
  `torchrun --standalone --nnodes=1 --nproc_per_node=2 main.py` from
  `/app/engine`, using the standard `MASTER_ADDR`/`MASTER_PORT`/`RANK`/
  `LOCAL_RANK`/`WORLD_SIZE` env vars that torchrun provides.
- `run.sh` — executable bash script `cd /app/engine` then launches the
  `torchrun` command above (export `OMP_NUM_THREADS=1` and set
  `torch.set_num_threads(1)` in code too).

Output files (all under `/app/engine/out/`):

- `out/w_stage0.pt` — written by **rank 0**: `torch.save` of a dict
  `{canonical_param_name: tensor}` for exactly the stage0 parameters
  (full tensors, canonical names from `reference.build_params()`).
- `out/w_stage1.pt` — written by **rank 1**: same for stage1 parameters.
- `out/report.json` — written by **rank 0 after a final `barrier()`** from
  the training its ranks actually performed:

```json
{
  "flavor": "main",
  "world": {"pipeline_stages": 2, "tensor_parallel_size": 1, "total_ranks": 2, "stage_ranks": {"stage0": [0], "stage1": [1]}},
  "model": {"vocab": 64, "d_model": 32, "n_heads": 8, "head_dim": 4, "layers": 6},
  "layers_per_stage": [3, 3],
  "training": {"steps": 4, "microbatches": 2, "microbatch_batch_size": 2, "seq_len": 16, "optimizer": "sgd", "lr": 0.05, "init_seed": 20260407},
  "per_step_microbatch_losses": [[5.5704, 5.4821], [5.4751, 5.6636], [5.4492, 5.3877], [4.9024, 5.0881]],
  "final_loss": 4.0745,
  "gradient_equivalence": {"max_abs_diff": 0.0, "max_rel_diff": 1e-06, "num_tensors_compared": 45},
  "outputs": {"weights": ["/app/engine/out/w_stage0.pt", "/app/engine/out/w_stage1.pt"]}
}
```

Semantics of the fields:

- `per_step_microbatch_losses`: 4 rows × 2 floats — for each global step, the
  `loss_m` observed at stage1 for micro 0 and micro 1 (order fixed). The
  verifier recomputes these from the canonical reference and tolerates small
  float drift.
- `final_loss`: the reference-style mean loss computed **after the final
  update** on steps-3 full batch with the saved parameters — i.e.
  `reference.loss(final_weights_dict, tokens[3])`.
- `gradient_equivalence`: from your own verification pass — at the **last
  step**, compare (a) your engine's accumulated mean gradients with
  (b) `reference.grads(weights_before_last_step, tokens[3])` for every
  parameter key your stage owns: record `max_abs_diff`,
  `max_rel_diff = max |a-b|/max(|b|,1e-8)`, and the number of tensors
  compared. These numbers must be small (gradients really equivalent), and
  they must be reproduced when you re-run.

## Required self-verification (do it, and keep the artifacts consistent)

1. **Forward equivalence**: run `reference.loss` on the same canonical init +
   micro tokens; your engine's per-micro losses must match within ~1e-3; the
   values you report must genuinely be the ones your engine measured (the
   verifier re-derives them independently).
2. **Gradient equivalence**: compare your accumulated mean gradients against
   `reference.grads` at the last step (as described above), and confirm
   `max_rel_diff < 0.02`.
3. **Final equivalence**: after saving, confirm
   `reference.loss(saved_all_params, tokens[3]) == final_loss` to ~1e-3.
4. **Run again**: `bash /app/engine/run.sh` must be rerunnable and produce
   the same numbers (float determinism), never leaving partial output.

## Grading

The verifier will (from its own pristine copy of `reference.py`, hidden from
you):

1. re-run `bash /app/engine/run.sh` (2 processes) and require exit 0, with
   `out/w_stage0.pt`, `out/w_stage1.pt`, `out/report.json` present and
   well-formed;
2. check the schema fields (flavor, world, model, layers_per_stage,
   training, losses, outputs) are exact;
3. recompute the canonical 4-step SGD loop and independently derive the
   reference final weights and per-micro loss rows;
4. verify the saved stage weights are the correct **partition** (stage0 has
   exactly the `embed`+`blocks.0..2` keys, stage1 exactly `blocks.3..5`+head
   keys; union = full set, no overlap) and that they match the canonical final
   weights (max abs diff < 5e-4);
5. verify all 8 per-microbatch losses and `final_loss` against the
   reference-derived values (abs tolerance 1e-2 for losses, 1e-3 for
   final_loss);
6. sanity-check `gradient_equivalence` (non-negative values, ≥ 30 tensors
   compared, `max_rel_diff < 0.01`, `max_abs_diff < 0.05`).  Because the
   pipeline reproduces the reference computation exactly, these values are
   typically ~0 (like the example above).

All checks must pass for full reward.