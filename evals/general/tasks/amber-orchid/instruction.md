# Merkstock Index Ledger — hardening a JSON REST service

You are a security engineer hardening the **Merkstock Index Ledger**, a small
REST service that queries a synthetic blockchain index and stores arbitrary
comments and token files. It is written in Python/Flask. Read this contract
fully before writing anything.

Everything you produce lives in `/app`. A verifier runs **your** artifacts in
fresh processes, so nothing may depend on your current shell.

Read-only fixtures under `/app` (do NOT modify):
* `helpers.py` — the legacy storage-layer **source**. Review it for the
  vulnerability it contains and record the exact CWE in your report below.
* `sanitizer.py` — the shared HTML filter used on comment renders. The verifier
  uses this same copy.
* `ledger.json` — the index data (block headers and transactions) the service
  serves.

## Targets

1. **`/app/api.py`** — a Flask service (run: `python3 /app/api.py [PORT]`,
   default port 8039) implementing the routes and semantics below.
2. **`/app/schema.json`** — the REST contract document, served verbatim at
   `GET /api/v1/doc.json`. It must be self-consistent with the implemented
   routes and carry the required security report.
3. **`/app/xss.html`** — a **stored-XSS proof-of-concept** payload that, after
   passing through `sanitizer.sanitize()`, still **auto-executes** JavaScript on
   page load (no click/focus/interaction) calling `alert("AMBERORCHID")`.

---

## Error envelope

Every error response is JSON: `{"error": {"code": <string>, "message": <string>}}`
with `code` in `{bad_request, not_found}`. Every **not_found** response must
contain **exactly one** top-level field `error` (no extra fields).

## Routes

### `GET /api/v1/health`
`200` JSON `{"status": "ok"}`. Used to prove the service stays reachable.

### `GET /api/v1/blocks?height=<n>`
`height` is **REQUIRED** and must be a plain, non-negative base-10 integer.
* Missing, empty (`?height=`), `-2`, `1.5`, `2x`, `abc`, or any value exceeding
  a 64-bit signed integer → `400 bad_request`.
* Valid integer in range `0..31` → `200` with the block object from
  `ledger.json` (`{"height":..., "hash":..., "prev_hash":..., "tx_count":...}`).
* A valid integer but out of range (e.g. `40`, `500`) → `404` `not_found`.

### `GET /api/v1/blocks/<hash>`
`<hash>` matching one of `ledger.json["blocks"][*]["hash"]` → `200` the block.
Anything else (unknown, malformed, or not 64 hex chars) → `404` `not_found`.

### `GET /api/v1/txs/<txid>`
`<txid>` matching one of `ledger.json["txs"][*]["id"]` → `200` that transaction.
Anything else (unknown, malformed, or wrong length) → `404` `not_found`.

### `POST /api/v1/uploads` — the upload endpoint
JSON body: `{"name": <filename>, "data": <base64>, "tokens": <int>}`.
Must neutralize path traversal:
* `name` must be a bare filename: non-empty, containing **no** `/`, no `\`, no
  `..` segment, not an absolute path, and no whitespace/control bytes. Any
  violation → `400` and **nothing written**.
* `data` must be valid base64 and `tokens` a non-negative integer, else `400`.
* Success → `201` `{"stored": <safe basename>, "size": <int>}`, writing the
  decoded bytes under `/app/uploads/` using a basename that can never escape
  that directory, and returning that same safe basename.

### `POST /api/v1/comments`
JSON body: `{"title": <str>, "body": <str>}`. Non-empty string `title` and
non-empty string `body` required (else `400`). Success → `201`
`{"id": <int>}`; ids are deterministic starting at 1.

### `GET /api/v1/comments/<id>/render`
`<id>` a positive integer (else `400`); unknown id → `404` `not_found`. Known id
→ `200` with `Content-Type: text/html; charset=utf-8`, the body being an HTML
document that interposes **`sanitizer.sanitize(comment["body"])`**. You MUST
route the comment through the shared filter — the headless browser loads this
served output.

---

## `schema.json` — security contract + report

Valid JSON served at `/api/v1/doc.json`. Must contain:
- `paths` with **every** route above (`/api/v1/health`, `/api/v1/blocks`,
  `/api/v1/blocks/{hash}`, `/api/v1/txs/{txid}`, `/api/v1/uploads`,
  `/api/v1/comments`, `/api/v1/comments/{id}/render`, `/api/v1/doc.json`), each
  documenting its method/params/responses tightly enough that a client reading
  only this doc can issue every call correctly.
- a `security.report` array. It must include the exact filepath-traversal entry
  for the weakness in `helpers.py`, with this **exact** CWE identifier:
  `{"cwe": "CWE-22", "file": "/app/helpers.py", "component": "store_token",
    "severity": "high", "status": "mitigated",
    "evidence": "POST /api/v1/uploads rejects traversal names and stays alive"}`

## `xss.html` — sanitizer-bypass deliverable

`sanitizer.sanitize` is a real blacklist filter (re-read its source). Build a
payload that **survives** it yet lets a browser auto-run `alert("AMBERORCHID")`
as soon as the headless Chromium loads the rendered output (no interaction). The
verifier POSTs your file as a comment `body`, renders it through `sanitize()`,
and loads the served HTML in headless Chromium — the dialog must appear.

Study the exact patterns the filter removes: a `<script>` element; any `on...=`
handler preceded by whitespace; `javascript:` URLs; and a blacklist of element
tags. Use an element the filter allows together with a handler form the filter
does not catch, so the payload still auto-executes.

---

## Constraints

- Work only under `/app`. Never read or depend on `/tests` or `/solution`.
- `api.py` must start cleanly from a fresh process, expose a WSGI `app`, and
  must **not** start the server when imported.
- Response statuses and JSON shapes must match the contract exactly; the
  single-`error`-field 404 rule is graded.
- Traversal must never reach outside `/app/uploads`; the service must remain
  reachable and functional after traversal attempts.
- The delivered `/app/api.py` is re-executed against hidden inputs in fresh
  processes, so your implementation must generalize; it is not limited to the
  visible fixtures.