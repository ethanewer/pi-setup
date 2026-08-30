# Ember Atlas — cache the Topoline LM for offline reuse

**Ember Atlas** needs a pretrained language model and its tokenizer pulled
from a model hub into a standard local cache so that later, fully offline
consumers can load them without any re-download.

## Environment

- Working directory: `/app`.
- A loopback-only **Ridgetop model hub** is reachable **right now**:
  - Endpoint: `http://127.0.0.1:8000`. It speaks a minimal Hugging Face
    Hub-compatible REST surface (it serves `GET /api/models/<repo_id>` and
    `GET /<repo_id>/resolve/<revision>/<filename>`), so
    `huggingface_hub.snapshot_download(..., endpoint=...)` works against it —
    or you can fetch with plain HTTP and build the cache yourself.
  - The served repo is **`ridge/topoline-24m`** (a tiny GPT2-style causal LM
    with a fast word-level tokenizer). Its source files live read-only under
    `/app/hub/ridge/topoline-24m`. Do **not** modify `/app/hub`,
    `/app/hub_server.py`, or `/app/entrypoint.sh`.
- Installed: `torch`, `transformers`, `huggingface_hub`, `safetensors`,
  standard library. No other network access is needed or allowed.
- Python 3.12 is available as `python3`.

## Deliverables (both required)

1. `/app/fetch_model.py` — a runnable CLI program with two subcommands:

   **fetch**
   ```
   python3 /app/fetch_model.py fetch --endpoint <url> --repo-id <id> --cache <dir>
   ```
   Downloads the model **and** its tokenizer from the hub into the standard
   Hugging Face cache layout under `--cache`, such that both of these succeed
   fully offline (no network, nothing re-downloaded):
   ```python
   AutoTokenizer.from_pretrained(repo_id, cache_dir=cache, local_files_only=True)
   AutoModelForCausalLM.from_pretrained(repo_id, cache_dir=cache, local_files_only=True)
   ```
   The cached snapshot must contain the model `config.json`, a model weight
   file, and the tokenizer assets. On success print one JSON object to stdout:
   ```json
   {"cached": "<repo_id>", "cache_dir": "<dir>", "files": ["config.json", ...], "revision": "<commit sha>"}
   ```
   (`files` = snapshot filenames, sorted; `revision` = the commit sha stored
   in the cache, i.e. the contents of `refs/main`.)
   On failure — endpoint unreachable, unknown repo id, a repo whose snapshot
   is missing the model config or the tokenizer, or any download error —
   print an error to stderr and **exit non-zero**, creating no usable cache.

   **verify**
   ```
   python3 /app/fetch_model.py verify --repo-id <id> --cache <dir> --prompt <text>
   ```
   Loads the tokenizer and model **straight from the cache** with
   `local_files_only=True` (it must never touch the network), then greedy-
   decodes exactly 4 new tokens (`max_new_tokens=4`, `do_sample=False`) and
   prints one JSON object to stdout:
   ```json
   {"repo_id": "<id>", "prompt": "<text>", "new_tokens": 4, "generated": "<decoded continuation>"}
   ```
   (`generated` is the decoded text of just the 4 new tokens.) On failure —
   cache dir missing/empty, prompt empty, or any load error — print an error
   to stderr and **exit non-zero**.

2. `/app/hf_cache/` — the cache produced by running your program on the
   shipped repo:
   ```
   python3 /app/fetch_model.py fetch --endpoint http://127.0.0.1:8000 \
       --repo-id ridge/topoline-24m --cache /app/hf_cache
   python3 /app/fetch_model.py verify --repo-id ridge/topoline-24m \
       --cache /app/hf_cache --prompt "the ridgetop sweep"
   ```

## Edge cases the verifier probes

- fetching **different repos** (other tiny models) from other hub endpoints
  on different ports, then verifying fully offline with the hub **shut
  down** — the generated text must match the true model;
- a repo whose snapshot is **missing the tokenizer** (fetch must fail with a
  non-zero exit and create no usable cache);
- an **unknown repo id** (fetch must fail, non-zero);
- **verify with a nonexistent cache directory** (must fail, non-zero);
- **verify with an empty prompt** (must fail, non-zero);
- the greedy decode must be deterministic and equal the reference model's.

## Hard constraints

- Work only under `/app` (plus any temp scratch). Never read `/tests` or
  `/solution`.
- The `verify` subcommand must perform **zero network I/O**: the verifier
  runs it after shutting every hub server down, so any attempt to re-download
  fails the task.
- Deterministic; use the standard cache layout (under `--cache`) so a later
  offline consumer can find the assets. No hard-coding of repo contents.
