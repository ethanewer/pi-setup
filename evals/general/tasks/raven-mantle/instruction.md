# Close out the raven-v1 self-play inference adapter

You are finishing the offline inference layer of a chess self-play engine named
**raven-v1**. A pretrained **causal decoder LM** plus its **byte-level BPE
tokenizer** are already baked into the image as fully offline files. You must
write one runnable inference adapter, `/app/infer.py`, that implements the
stages below, then run it once so the default outputs land at
`/app/loss.txt` and `/app/batch_plan.json`.

The grading harness re-runs `/app/infer.py` on **different (hidden) data sets**
whose bag sizes, state counts, class counts, request streams, probe text, and
class counts all change. Your program must treat every shape as coming from its
input or from `/app/config.json`, never hard-code the visible fixtures'
dimensions.

## Shipped assets (already in the image)

- `/app/engine/model` — the causal-LM checkpoint (config + weights).
- `/app/engine/tokenizer` — the BPE tokenizer.
- `/app/config.json` — geometry used at run time:
  - `feat_dim` — width of every instance/state feature row.
  - `encoder_hidden` — hidden width of the bag encoder and of the WDL encoder.
  - `milp_classes` — how many logits the bag classifier returns.
  - `wdl_outcomes` — length of the post-softmax outcome vector (2.. large).
  - `lm_mb` — the LM micro-batch size used for loss accumulation.
  - `model_dir`, `tokenizer_dir`, `default_head_count`, `baseline_sha`.
- `/app/input/` — shipped fixtures for the default run:
  - `probe.txt` — one probe prompt per line.
  - `bag.npz` tuple `X` (float32, `(T, feat_dim)`) — a bag of instance features.
  - `state.npz` tuple `X` (float32, `(k, feat_dim)`) — the current position's
    `k` legal-move candidate features.
  - `requests.json` — a streaming request log plus a budget (schema below).
  - `headcount.json` — `{"count": N}` default class count for reconfiguration.

**Hard constraint:** `/app/engine/` is the immutable vendor checkpoint. Do not
modify, delete, or rewrite any file under it; the harness re-hashes it
byte-for-byte after your run.

## Deliverables

1. `/app/infer.py` — the executable CLI adapter (shebang + `chmod +x`).
2. `/app/loss.txt` — the loss-floor output written by the default run.
3. `/app/batch_plan.json` — the streaming batch plan written by the default run.

## CLI contract (exact subcommands)

```
python3 /app/infer.py lm     --input <probe.txt>  --output <loss.txt>
python3 /app/infer.py head    --count <N>         --output <outdir>
python3 /app/infer.py milp    --input <bag.npz>   --output <out.json>
python3 /app/infer.py wdl     --input <state.npz> --output <out.json>
python3 /app/infer.py batch   --input <requests.json> --output <plan.json>
python3 /app/infer.py workflow
```

The harness runs the individual subcommands with its own absolute paths (hidden
data under mount points like `/tmp/...`). Each subcommand must work from any
working directory and read only the file(s) it is given plus the committed
`/app/config.json` and `/app/engine/*`. Exit 0 on success.

`workflow` performs the whole default run over `/app/input/` (producing
`/app/loss.txt`, `/app/batch_plan.json`, and informational `out/…` JSONs). This
is exactly how you (and the harness) produce the three deliverables.

## Mode 1 — `lm`: local causal-LM forward + loss floor

Load the tokenizer and causal LM from `/app/engine/tokenizer` and
`/app/engine/model` strictly local-only (`local_files_only=True`). For each
non-empty line of the probe file, tokenize it and run a forward with those ids as
`labels` to obtain the standard LM cross-entropy loss for that line.

Aggregate the per-line losses into consecutive **micro-batches of size
`lm_mb`** (the final micro-batch may be shorter), take the **mean loss of each
micro-batch**, and write the **mean of those per-micro-batch means** to
`<loss.txt>` as a rounded 4-decimal float (`%.4f`).

This is the "rescale by the micro-batch count and accumulate so the total
matches the reference that averages over micro-batches" contract: because you
average per-micro-batch **means** (not re-average all samples), a trailing
short micro-batch legitimately changes the answer. Your result must be within
`1e-3` of the reference computed the same way. It must also be **below `9.0`**
(the model is pretrained; `log(vocab_size)` is larger than 9).

## Mode 2 — `head`: reconfigure the sequence classifier head for a custom count

Load the causal LM's base from `/app/engine/model` (local-only, do not touch
the checkpoint), and reconfigure it into a sequence-classification model with
**exactly `count` output labels** (e.g. via `AutoModelForSequenceClassification
with `num_labels=count`, `ignore_mismatched_sizes=True`). Save the reconfigured
model + config into `<outdir>`. The harness reloads it and asserts the saved
config's `num_labels` equals `count` and that a forward on a token probe gives
`(1, count)` logits. Any count (>=1) must work.

## Mode 3 — `milp`: bag-of-instances (MIL) forward

Given `<bag.npz>` (`X` = a single bag of `T` instances), wire an **instance
encoder** (`feat_dim` -> `encoder_hidden`, ReLU), an **attention gate** over
encoded instances that produces per-instance weights which **sum to 1**, and a
**bag classifier** reading the attention-weighted bag to give `milp_classes`
logits.

Write `<out.json>`:
```
{"logits": [milp_classes floats], "attention": [T floats], "instance_count": T}
```
- `logits` has exactly `milp_classes` entries.
- `attention` has exactly `T` entries and sums to `1 ± 1e-4`.

Edge case probed by hidden tests — **empty bag** (`T == 0`): must not crash;
return `logits` of length `milp_classes` (all zeros) and an **empty** `attention`
list.

## Mode 4 — `wdl`: policy / WDL head forward

Given `<state>` (`X` has `k` legal-move candidates), produce one **policy logit
per legal move** **and** a **post-softmax outcome vector** of length
`wdl_outcomes` that **sums to 1 ± 1e-4**.

Write `out.json`:
```
{"legal_logits": [k floats], "outcome_probs": [wdl_outcomes floats],
 "outcomes": wdl_outcomes, "legal_count": k}
```

Edge case probed by hidden tests — `k == 0`: must not crash; return an empty
`legal_logits` list and a still-valid `outcome_probs` (length `wdl_outcomes`,
summing to 1).

## Mode 5 — `batch`: bundle requests into aligned micro-batches

`<requests.json>`:
```
{"budget": {"mb": int, "window": int, "batch_tok": int, "granularity": int, "windows": int},
 "requests": [{"id": str, "tokens": int}, ...]}
```
Group the stream (preserve arrival order) into micro-batches, satisfying **all
four metric thresholds at once**:

1. **Granularity/alignment** — every micro-batch `tokens` is a positive
   multiple of `budget.granularity` (`tokens % granularity == 0`).
2. **Latency/cost per batch** — every micro-batch `tokens` is `<= batch_tok`.
3. **Window cap** — each window's total `tokens` (sum of its micro-batches) is
   `<= budget.window`.
4. **Flight count** — the total number of windows is `<= budget.windows`.

Every request id must appear **exactly once** (none duplicated, none missing).
Group the micro-batches into windows; each window may hold one or more
micro-batches. All requests' `tokens` are already multiples of `granularity`,
so a valid grouping always exists. The harness checks the constraints (any
valid arrangement passes; there is no single "best" grouping).

Write `<plan.json>`:
```
{"budget": {..same budget..}, "windows": [
   {"window_id": "w0", "tokens": <int>,
    "microbatches": [{"batch_id": "b0-0", "requests": [ids], "tokens": <int>}] }]}
```

## Mode 6 — `workflow`: default run / deliverable producer

Runs `lm` on `/app/input/probe.txt` -> `/app/loss.txt`, `batch` on
`/app/input/requests.json` -> `/app/batch_plan.json`, and (informational)
`milp`, `wdl`, `head` on the shipped inputs writing under `/app/out/`. After it
completes, the three deliverables must exist.

## Constraints

- Load the LM/tokenizer only from the committed local files with
  `local_files_only=True` — never attempt a download or network access.
- Do not modify `/app/engine/` or `/app/config.json`.
- Produce outputs by executing your model/network/planner — never by copying a
  precomputed literal.
- Your code must also compile (`python3 -m py_compile`).
- Exit 0 on any valid hidden input following the schemas above.