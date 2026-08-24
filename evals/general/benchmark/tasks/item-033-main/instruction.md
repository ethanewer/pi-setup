# Build a tokenizer-based HTTP JSON API

In `/app/model` there is a **pre-downloaded, offline** Hugging Face tokenizer (a small Byte-Level BPE
"GPT2-style" model). It contains `tokenizer.json`, `tokenizer_config.json`,
`special_tokens_map.json`, and `model_meta.json`. This local copy is what your service must use so that
**downloads are reproducible**: you must load it offline (`local_files_only=True`) — never query the
Hugging Face network — and honor a pinned local cache so a fresh start returns identical outputs.

## Objective

Build an HTTP JSON API in Python with Flask. Deliverables:

- `/app/server.py` — a runnable Flask service exposing two documented endpoints and which **pauses its
  own startup until it has loaded the tokenizer offline**.
- `/app/client_test.py` — a runnable test client that **separates service startup from request
  testing**: it waits for the service to be ready, then sends positive and negative requests and records
  results.

### The service (`/app/server.py`)

- Read the port from the environment variable `PORT` (default `5000`). Listen on `0.0.0.0`.
- Before serving, load the tokenizer with:
  `AutoTokenizer.from_pretrained("/app/model", local_files_only=True)`.
- Endpoints:
  - `GET /health` → `200` with JSON `{"status":"ok"}`. It must only return `ok` **after** the tokenizer
    is fully loaded (i.e. readiness is meaningful).
  - `POST /tokenize` with a JSON body `{"text": string, "add_special_tokens": bool?}` (default
    `add_special_tokens=true`) → `200` with
    `{"tokens": [<str>], "ids": [<int>], "add_special_tokens": <bool>}`.
    - `tokens` = the list of token strings from `convert_ids_to_tokens(...)`.
    - `ids` = the integer input ids from the tokenization.
  - **Negative paths**: an unparsable/none-JSON body, a missing/invalid `text`, or a non-string `text`
    → `400` with JSON `{"error": "<message>"}`.
- Print the line `READY` to stdout once the server is bound and ready.

### The test client (`/app/client_test.py`)

Write a single self-contained client that:
1. Launches `/app/server.py` (or connects to an already-running instance on `PORT`).
2. **Waits for real readiness**: polls `GET /health` until it returns 200 (timeout ~60 s).
3. Performs a **positive** test: compute the expected `ids` locally with the same offline tokenizer
   (`AutoTokenizer.from_pretrained("/app/model", local_files_only=True)`), then
   `POST /tokenize` on the same text and assert the server's `ids` matches.
4. Performs **negative** checks: `POST /tokenize` with a JSON body that lacks a `text` field (expect
   `400`), and a body that is not valid JSON (expect `400`).
5. Writes `/app/api_results.json`:
   ```json
   {"health_ok": true, "positive": true, "negative": true, "checked_text": "<...>"}
   ```
6. Records how each check went; the service may keep running afterward (do not worry about shutting it
   down when the verifier re-probes it later).

## Requirements

- `server.py` and `client_test.py` must be self-contained Python files using only `flask`, `transformers`,
  and the standard library. No other third-party packages.
- The service **must not** try to reach the network for the model — it must use the offline local copy at
  `/app/model` deterministically and reproducibly.
- Run `client_test.py` so that `/app/api_results.json` is produced. The `positive`, `negative`, and
  `health` checks must all be `true`.

The reward checks that a live server running `/app/server.py` on a fresh port answers `/health` and
`/tokenize` correctly (positive and negative), using the same offline tokenizer you have in
`/app/model`.