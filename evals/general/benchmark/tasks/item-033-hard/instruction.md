# A reproducible tokenizer HTTP JSON API (batch, truncation, concurrency)

In `/app/model` there is a pre-downloaded, **offline** Hugging Face Byte-Level BPE tokenizer (`tokenizer.json`,
`tokenizer_config.json`, `special_tokens_map.json`, and `model_meta.json`). The `model_meta.json` file records the
exact revision your service must report. The whole point is **reproducible downloads**: load it with
`local_files_only=True` from the local cache, never touch the Hugging Face network, and expose a stable revision so
that two identical starts yield identical results.

## Objective

Build a robust Flask service at `/app/server.py` that:

1. **Separates service startup from request testing.** The tokenizer is loaded at startup before binding; the
   service prints `READY` once it is bound and serving, and `/health` only returns `200` once ready.
2. Supports **single** and **batch** tokenization, with optional truncation.
3. Stays correct under **concurrent overlapping requests** (a shared tokenizer used from many threads).
4. Returns `400` (negative) for malformed / missing / invalid-mode requests.
5. Exposes a **model-metadata** endpoint so clients can verify the exact offline artifact (reproducibility).

### Endpoints

- `GET /health` → `200 {"status":"ok"}` (only when ready).
- `GET /model` → `200` with the parsed content of `/app/model/model_meta.json` merged with
  `{"offline": true, "loaded_revision": "<revision from model_meta.json>"}`.
- `POST /tokenize` (single): body `{"text": str, "add_special_tokens": bool?=true}` →
  `200 {"text": str, "tokens": [str, ...], "ids": [int, ...], "add_special_tokens": bool}`.
  - `tokens` = `convert_ids_to_tokens(ids)`.
- `POST /batch`: body `{"texts": [str,...] (non-empty), "add_special_tokens": bool?=true,
  "max_length": int? (optional, >0), "truncation": bool?=true}` →
  `200 {"results": [{"text": t, "tokens": [...], "ids": [...]}, ...]}`.
  When `truncation=true` and a positive `max_length` is given, truncate each `ids`/`tokens` list to
  `max_length` items.
- **Negative (`400`)** for: unparsable/non-JSON body, missing or non-string `text`, an `texts` that is not a
  non-empty list of non-empty strings, and a `max_length` that is not a positive integer when provided. Each
  returns `{"error": "<message>"}`.

Run Flask with its threaded default so that many concurrent calls work; keep the tokenizer read path
non-mutating/thread-safe.

### Client test — `/app/client_test.py`

Write a self-contained client that:
1. Launches `/app/server.py` on `PORT` (default `5000`) and polls `/health` until ready.
2. Checks `GET /model` reports the revision from `/app/model/model_meta.json`.
3. Positive single: several distinct texts; the server's `ids` must equal ids computed locally with the same
   offline tokenizer (same `add_special_tokens`).
4. Positive batch: `/batch` over several texts; every result's `ids` matches local.
5. Truncation positive: `/batch` with `{"max_length":4,"truncation":true}` → every `ids` length `<=4` and a
   prefix of the local full tokenization.
6. Negative: missing `text`, missing `texts`, empty list, non-JSON body, non-string element → all `400`.
7. Concurrency stress: 6 threads × several simultaneous `/batch` and `/tokenize` requests on distinct texts; all
   must return correct IDs (thread-safe, no cross-talk).
8. Writes `/app/batch_results.json`:
   ```json
   {"health_ok":true,"model_revision":true,"single_pos":true,"batch_pos":true,
    "truncation":true,"negative":true,"concurrency":true}
   ```
   All fields must be `true`.

`server.py` and `client_test.py` must be self-contained and use only `flask`, `transformers`, and the standard
library. Run the client so `/app/batch_results.json` is produced. The reward boots `/app/server.py` freshly on a
fresh port and checks: readiness, model-revision, single+batch (incl. truncation), negative responses, and
overlapping-request consistency.