# frost-quay — Offline encoder export bench

You are taking over an **offline model-export bench**. The bench loads a
HuggingFace-format encoder checkpoint from local disk with the platform's
preinstalled ML toolchain, pushes a fixed probe sequence through the model, and
writes a machine-readable export report. Everything must work **without any
network access** and **without disturbing the pinned toolchain**.

## Environment

Working directory `/app` contains:

- `/app/model_repo/` — the visible tiny encoder checkpoint in HF format
  (complete: `config.json` + weights; loadable fully offline).
- `/app/toolchain_pins.json` — the **pristine baseline** recording the exact
  `torch` and `transformers` versions the platform preinstalled. Read-only.
- `/app/legacy_stack.txt` and `/app/refresh_legacy.sh` — a **deprecated**
  2019-era downgrade bundle left by a retired team. It pins ancient versions
  whose API signatures differ from the current toolchain. **Do not run it and
  do not install anything from it** — the export contract below is only
  satisfiable with the pinned, unmodified toolchain.

**You must not modify, move, or delete** `/app/model_repo/`,
`/app/toolchain_pins.json`, `/app/legacy_stack.txt`, or
`/app/refresh_legacy.sh`. You must **not** upgrade, downgrade, uninstall, or
reinstall `torch` or `transformers` — the bench refuses exports produced by a
drifted toolchain.

## Deliverables (both required)

1. `/app/export.py` — a runnable Python program with this interface:
   ```
   python3 /app/export.py <model_dir> <output_json>
   ```
   It must work on **any** HF-format encoder checkpoint directory that follows
   the bench conventions below — not just `/app/model_repo`.

2. `/app/export_report.json` — the report your program writes when run as:
   ```
   python3 /app/export.py /app/model_repo /app/export_report.json
   ```

## Export contract

`/app/export.py` must:

- Force offline mode **before** importing `transformers`: set the environment
  variables `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` at the very start
  of the program (before any `transformers` import). No network access is
  available or allowed.
- Load the model with `transformers.AutoModel.from_pretrained(<model_dir>)`
  and put it in evaluation mode.
- Build the fixed probe input on the model's device (CPU):
  - `input_ids = [[0, 1, 2, 3, 4, 5, 6, 7]]` — but truncate the list to the
    model's vocabulary size (`config.vocab_size`) if that is smaller than 8.
  - `attention_mask` = all ones, same shape.
- Run a forward pass under `torch.no_grad()` and take
  `outputs.last_hidden_state`.
- Write `output_json` as a JSON object with **exactly** these keys:

```json
{
  "model_dir": "<the <model_dir> argument, exactly as passed>",
  "torch_version": "<torch.__version__>",
  "transformers_version": "<transformers.__version__>",
  "hidden_size": <int: model.config.hidden_size>,
  "num_parameters": <int: total trainable parameter count>,
  "last_hidden_checksum": <float: sum of every element of
                           last_hidden_state, rounded to 6 decimal places>
}
```

- Report the versions **as actually detected at run time** via
  `torch.__version__` and `transformers.__version__` — do not hardcode them.
- `num_parameters` is `sum(p.numel() for p in model.parameters())`.

## How it is graded

The verifier runs your `/app/export.py` **unchanged**:

- on the visible `/app/model_repo`, and checks that `/app/export_report.json`
  matches an independently computed reference (computed with the platform
  toolchain inside the same container);
- on several **hidden** tiny encoder checkpoints that the verifier constructs
  with the pinned toolchain at verify time (different seeds, hidden sizes,
  layer counts, and vocab sizes), written to scratch directories, and checks
  the report your program produces against its own independent computation.

It then verifies the platform toolchain is **exactly** the pinned baseline
(recorded in the pristine `/app/toolchain_pins.json`): the installed
distributions, their runtime `__version__` strings, and a live forward pass
must all be intact. Any downgrade, replacement, duplicate install, or other
drift of `torch`/`transformers` fails the bench.

## Constraints

- No network access at verify time; use only what is preinstalled.
- Do not hardcode outputs for `/app/model_repo` — the hidden checkpoints have
  different sizes, layer counts, and vocabularies.
- Do not modify any file that was already in `/app` when you started.
- The verifier has a 300 s budget; the bench is tiny, so keep the export path
  simple and direct.
