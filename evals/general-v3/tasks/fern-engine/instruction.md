# fern-engine: a model-serve lifecycle pipeline

You are wiring up a small, fully local model-serve pipeline: caching a
pretrained language model + tokenizer for offline reuse, reloading it offline,
training + serializing a small classifier into a canonical loadable artifact,
reconstructing an architecture from a raw state dict, and re-targeting a saved
classifier to a different label count.

You must deliver exactly two things, both under `/app`:

- `/app/workflow.py` — a single CLI program implementing every subcommand below.
- `/app/artifact/` — a directory produced by *running* the `train` subcommand
  of your program on the provided visible training data (see "What you must do").

Everything is CPU-only and fully offline. Installed libraries: `torch`,
`transformers`, `safetensors`. Use only these plus the Python standard library.

## Provided fixtures (do NOT modify or overwrite them)

- `/app/pretrained_lm/` — a tiny pretrained **causal LM** saved by Hugging
  Face. Contains a `config.json` (a GPT2-style cariety), a model weight file,
  and a tokenizer (`vocab.txt` + `tokenizer_config.json`). This stands in for a
  model you would normally download from a hub.
- `/app/state_seed.pkl` — a **torch pickle of a `state_dict`** describing a
  fully-connected classifier (a `FernClassifier`, defined below).
- `/app/base_clf/` — a saved `FernClassifier` (a `config.json` +
  `state.pt`).
- `/app/data/train.csv` — training rows for the classifier.
- `/app/data/eval.csv` — feature-only rows (no label column) for inference.
- `/app/base_eval.csv` — feature-only rows matching `/app/base_clf/`.

## The shared architecture: FernClassifier

All four classifier-related subcommands build, save, and reload the SAME
module, `FernClassifier`, defined exactly as:

```python
class FernClassifier(nn.Module):
    def __init__(self, in_features, hidden_size, num_labels):
        super().__init__()
        self.encoder = nn.Linear(in_features, hidden_size)
        self.head    = nn.Linear(hidden_size, num_labels)
    def forward(self, x):
        return self.head(torch.tanh(self.encoder(x)))
```

Its saved `state_dict` therefore has exactly four keys:
`encoder.weight`, `encoder.bias`, `head.weight`, `head.bias`, with shapes
`[hidden_size, in_features]`, `[hidden_size]`, `[num_labels, hidden_size]`,
and `[num_labels]` respectively. A saved model directory is
`config.json` + `state.pt`, where `config.json` is

```json
{"in_features": 5, "hidden_size": 6, "num_labels": 3}
```

and `state.pt` is `torch.save(model.state_dict(), ...)`.

## The driver: `/app/workflow.py`

Invoke it as `python3 /app/workflow.py SUBCOMMAND ARGS...`. Each subcommand
prints a single JSON object to stdout on success. On ANY malformed input, the
program must exit with a NON-zero status and state the reason on stderr; it
must never print an output JSON on failure.

CLI argument count per subcommand is fixed; wrong counts must exit non-zero.

### 1) `cache SOURCE_DIR CACHE_DIR`
Persist the pretrained causal LM (architecture + weights) **and** its
tokenizer from `SOURCE_DIR` into `CACHE_DIR`, such that a later consumer can
load the whole thing fully offline with `local_files_only=True`. Use the
transformers APIs (`AutoModelForCausalLM.from_pretrained` + `.save_pretrained`,
and the tokenizer with `AutoTokenizer.from_pretrained` + `.save_pretrained`).
`CACHE_DIR` must then contain the model `config.json`, a model weight file,
and the tokenizer files (`vocab.txt` / `tokenizer_config.json`). On success
print `{"cached": "<CACHE_DIR>", "files": [...]}`.

Edge cases (must fail): `SOURCE_DIR` has no usable model config; `SOURCE_DIR`
has no tokenizer.

### 2) `offline CACHE_DIR PROMPT`
With the network disabled, load the causal LM and its tokenizer straight from
`CACHE_DIR` using `local_files_only=True` (never touching any network, never
reading the original source), then greedy-generate. Contract:

- PROMPT is a non-empty printable string.
- Load the tokenizer + model from `CACHE_DIR` with `local_files_only=True`.
- `model.generate()` with `max_new_tokens = 4`, deterministic greedy decoding
  (`do_sample=False`, no seed). Exactly 4 brand-new tokens must be produced
  regardless of config EOS (disable early stopping so `new_tokens` is always 4).
- Print `{"prompt": "<PROMPT>", "new_tokens": 4, "generated": "<decoded text>"}`.

Edge cases (must fail): `CACHE_DIR` does not exist; PROMPT is empty.

### 3) `train DATA.csv OUT_DIR`
Train a `FernClassifier` for classification on the numeric rows in `DATA.csv`
and serialize it to `OUT_DIR` as the canonical loadable artifact. Contract:

- `DATA.csv` layout: header row of feature column names followed by one final
  float feature per data row, then an integer label column. Example header +
  rows: `f1,f2,f3,label` with values like `1.0,0.0,0.0,0`.
- `in_features = number of feature columns`; `num_labels = (max label)+1`;
  pick `hidden_size = 8`.
- Train deterministically (fixed seed, fixed epoch count) with
  cross-entropy loss on the MLP forward pass.
- Save `config.json` + `state.pt` into `OUT_DIR`.
- Then **reload** the artifact you just wrote (build the same module from the
  saved config and load the saved state) and confirm it reproduces `argmax`
  predictions on the training rows exactly.
- Print `{"artifact": "<OUT_DIR>", "num_labels": K, "reload_ok": true, "rows_seen": N}`.

Edge cases (must fail): DATA.csv missing; CSV has no data rows; fewer than two
distinct labels; non-numeric entries; ragged rows.

### 4) `predict MODEL_DIR INPUT.csv`
Load a saved `FernClassifier` from `MODEL_DIR` (its `config.json` +
`state.pt`), read `INPUT.csv` (header of feature columns then feature-only
rows), and print `{"predictions": [int,...], "num_labels": K}` — one integer
`argmax` class per row. Must be deterministic; must not retrain.

Edge cases (must fail): `MODEL_DIR` missing/no `config.json`; INPUT missing;
INPUT empty; feature-width mismatch.

### 5) `rebuild STATE.pkl OUT_DIR`
`STATE.pkl` is a torch pickle of a raw `state_dict` that a particular
`FernClassifier` would produce. Reconstruct the matching architecture (derive
`in_features`, `hidden_size`, `num_labels` purely from the tensor shapes),
construct the module so it loads that exact dict with
`load_state_dict(..., strict=True)`, and save the loaded model to `OUT_DIR`.
Print `{"in_features", "hidden_size", "num_labels", "loaded": true}`.

Edge cases (must fail): file is not a loadable `state_dict` (e.g. not a torch
pickle); keys differ from the canonical four `encoder.{weight,bias}`
`head.{weight,bias}`; tensor shapes inconsistent.

### 6) `reconfigure BASE_DIR OUT_DIR K`
Read the saved `FernClassifier` config in `BASE_DIR` (its `in_features` and
`hidden_size`), and instantiate a fresh `FernClassifier` with the SAME
features/hidden but with the full-size head sliced to exactly `K` output
labels, save it into `OUT_DIR` (config with `num_labels = K` + `state.pt`).
Print `{"base": "<BASE_DIR>", "num_labels": K, "out_dir": "<OUT_DIR>"}`.

Edge cases (must fail): `BASE_DIR` has no `config.json`; `K` is not an integer
or `K < 1`.

## What you must produce

1. Write `/app/workflow.py` implementing it all, making it executable.
2. Run your own program to create the artifact deliverable:
   `python3 /app/workflow.py train /app/data/train.csv /app/artifact`

`/app/artifact/` must be the successfully-serialized classifier from #2.

The verifier re-runs EVERY subcommand on fresh hidden inputs (a different
pretrained LM, a different state dict shape, a different label count, unseen
training data) and also feeds malformed inputs (bad state file, header-only
CSV, nonexistent cache, `K=0`, missing input) requiring graceful non-zero
exits. Keep your outputs deterministic — no random seeds in production paths.