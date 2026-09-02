# Brass Lantern — generate the LoRA adapter config for a causal model

The Brass Lantern tuning desk parameterises LoRA (low-rank adaptation) runs
from compact **model cards**. Your job: write a reusable generator that turns
a model card into a PEFT-style **adapter config** JSON, and run it on the
provided card to produce the shipped config.

## Provided data (read-only; do not modify)

- `/app/model_card.json` — the visible model card describing a small causal
  (autoregressive) network and its LoRA hyperparameters.

## Deliverables (both required)

1. `/app/make_adapter.py` — the reusable generator with exactly this CLI:
   ```
   python3 /app/make_adapter.py <card.json> <out.json> [--rank <int>] [--alpha <int>]
   ```
   `--rank` / `--alpha`, when given, **override** the card's
   `lora.r` / `lora.lora_alpha`. When absent, the card values are used.

2. `/app/adapter_config.json` — the config produced by running your program
   on the visible card **without** override flags:
   ```
   python3 /app/make_adapter.py /app/model_card.json /app/adapter_config.json
   ```

## Model card schema

```json
{
  "model_name": "<string>",
  "arch": "causal_decoder",
  "modules": [
    {"name": "<dotted module path>", "type": "Embedding|Linear|Conv1D|LayerNorm|Dropout",
     "head": true,          // optional; only the output head carries this
     "trainable": false}    // optional; absent means trainable
  ],
  "lora": {"r": <int>, "lora_alpha": <int>, "lora_dropout": <float>}
}
```

## Required derivation rules

From the card you must derive the adapter config as follows:

- **LoRA-targetable module types** are `Linear` and `Conv1D` only.
  `Embedding`, `LayerNorm`, `Dropout`, and any other type are never targeted.
- The output head is the module with `"head": true`. It is **never** part of
  `target_modules`; instead its name goes into `modules_to_save` (saved and
  trained in full).
- A module with `"trainable": false` is **excluded entirely** — from both
  `target_modules` and `modules_to_save` (this precedence beats `"head":
  true`).
- Lists are sorted **lexicographically** by module name (plain string sort —
  e.g. `"...h.10..."` sorts before `"...h.2..."`).

The emitted config JSON must contain **exactly** these keys:

```json
{
  "r": <int>,                                   // card lora.r, or the --rank override
  "lora_alpha": <int>,                          // card lora.lora_alpha, or --alpha override
  "lora_dropout": <float>,                      // card lora.lora_dropout verbatim
  "target_modules": [<sorted module names>],
  "modules_to_save": [<sorted module names>],
  "bias": "none",
  "task_type": "CAUSAL_LM",
  "base_model_name_or_path": "<card model_name>",
  "inference_mode": true
}
```

`task_type` is always the literal `"CAUSAL_LM"` (the task is causal language
modelling), `bias` is always `"none"`, and `inference_mode` is always `true`.

## Edge cases the grader probes with hidden cards

- A frozen (`"trainable": false`) attention/MLP projection must be excluded
  from `target_modules`.
- A frozen module that also has `"head": true` must appear in **neither**
  list.
- `Conv1D` modules are targeted exactly like `Linear` ones.
- Lexicographic list ordering with nested numeric path segments
  (`...h.10...` before `...h.2...`).
- A card producing an **empty** `target_modules` (no targetable trainable
  non-head modules) must still emit a valid config with `"target_modules": []`.
- CLI overrides: `--rank` / `--alpha` (individually and together) must beat
  the card values; unspecified fields keep their card values.

## Constraints

- The grader runs `/app/make_adapter.py` **unchanged** on hidden cards (and
  with hidden flag combinations), comparing the full emitted JSON to the
  reference — do not hard-code the visible card, module names, or values.
- Do not modify `/app/model_card.json`.
- No network access; Python 3.12 standard library only (no `peft` needed —
  this is a config-generation exercise).
