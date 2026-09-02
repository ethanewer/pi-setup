# Gale Vault Inbox — hardening a customer-note REST service

You are a security engineer working on the **Gale Vault Inbox** service: a small
HTTP API that stores customer notes and re-serves them. The service is written
in Python/Flask. Your job is to harden it and evidence the remaining weakness.

Everything you produce lands in `/app`. A verifier later executes **your**
artefacts in fresh processes, so nothing may depend on your current session.

Read `/app/legacy_headers.py` (the original, buggy header canonicalizer) and
`/app/sanitizer.py` (the shared render-time HTML filter — **do not modify** it;
the verifier uses the same copy). Read this whole contract before starting.

---

## Deliverables

1. **`/app/api.py`** — the hardened Flask service (run: `python3 /app/api.py [PORT]`).
   It must implement the routes and semantics below, and expose drop-in function
   `canonical_header` plus a WSGI `app` for the verifier to import.
2. **`/app/schema.json`** — the REST contract doc, served verbatim by the API at
   `GET /api/v1/doc.json`. Read it, keep it self-consistent with the implemented
   routes, and include the required vulnerability inventory (below).
3. **`/app/xss.html`** — a **stored-XSS proof-of-concept payload** crafted so that,
   after it is passed through `sanitizer.sanitize()`, it still **auto-executes a
   browser `alert()` dialog as soon as the page loads** (no click/focus, no
   interaction). Use the marker string `GALEVAULT` inside the alert message.

---

## The service (`/app/api.py`)

Model a customer note as `{id, title, headers, body, tags}` stored in memory
(id assigns sequentially starting at 1). Implement exactly these routes:

### `POST /api/v1/notes` — the live REST upload endpoint
Request body JSON `{ "title": ..., "body": ..., "tags": [...], "header": {...} }`.
* `title` required, non-empty string, else **HTTP 400**.
* `body` required string, else **HTTP 400**.
* `tags` optional array of strings.
* `header` OPTIONAL object. Each key is an HTTP header name that you canonicalize
  via `canonical_header`; if **any key contains a control character** you must
  return **HTTP 400** (defence against header injection / response splitting).
  Stored headers use the canonical name.
* Success → **HTTP 201** `{"id": <int>, "title": "<title>"}`.

### `GET /api/v1/notes?limit=<uint>` — list
`limit` is **REQUIRED** and must be a non-negative integer (`[0-9]+`). Missing,
non-integer, or negative → **HTTP 400**. Success → `{"count": n, "notes": [...]}`,
the first `limit` notes (each with `id`, `title`, `tags`, and canonical
`headers` keys).

### `GET /api/v1/notes/<id>` — detail
* `id` not a positive integer (e.g. `abc`, `0`, `-1`) → **HTTP 400**.
* `id` exists → **HTTP 200** `{id, title, headers, tags, body}`.
* well-formed `id` that does not exist → **HTTP 404**, and a **structured not-found
  error**: `{"error": {"code": "not_found", "id": <int>, "message": "no such note"}}`.

### `GET /api/v1/notes/<id>/render` — render as HTML
Same `id` rules as detail (400 / 404). Returns `200` with `Content-Type:
text/html` and body equal to **`sanitizer.sanitize(rec["body"])` — you MUST route
the note body through the shared filter**. This is what a headless browser loads.

### `GET /api/v1/doc.json`
Returns the delivered `/app/schema.json` as JSON.

### `canonical_header(name)` — the hardening you author
Fixed replacement for the buggy legacy normalizer (see `legacy contract.py`):
* raises `ValueError` when `name` is not a non-empty string **or** any char has
  `ord < 0x20` or `ord == 0x7f` (control characters, incl. CR/LF/NUL);
* otherwise returns the canonical **title form**: split on `-`, uppercase the
  first letter and lowercase the rest of each token, rejoin with `-`. Examples:
  `content-type → Content-Type`, `Accept → Accept`, `x-note-id → X-Note-Id`,
  `cache-control → Cache-Control`, `x-Custom-Header → X-Custom-Header`.

Every error response is **structured JSON**: `{"error": {"code": <string>,
"message": <string>}}`. Use `code` values `bad_request` and `not_found`.

---

## `schema.json` — contract doc + vulnerability inventory

Valid JSON served at `/api/v1/doc.json`. It must, at minimum, contain:
* `paths` keys for all endpoints: `/api/v1/notes` (post+get), `/api/v1/notes/{id}`,
  `/api/v1/notes/{id}/render`, and `/api/v1/doc.json`, each describing its
  method/params/responses enough that a client reading ONLY this doc can issue
  every call correctly.
* a `security.vulnerabilities` array with at least these two entries (exact
  `cwe` values required):
  * `{"cwe": "CWE-79", ...}` — stored XSS in `/render`, status `open`, evidenced
    by `/app/xss.html`.
  * `{"cwe": "CWE-113", ...}` — header canonicalization control-character
    injection in `POST`, status `mitigated`, evidenced by `canonical_header`.

---

## `xss.html` — the sanitizer-bypass deliverable

`sanitizer.sanitize` is a real blacklist filter: it removes `<script>` tags,
event-handler attributes that follow *whitespace* (`on...=`), `javascript:` URLs,
and a set of element types. Find a payload that **survives** that filter while a
real browser still executes it automatically on load using the string
`GALEVAULT` in the alert message. Your file must actually deploy through the
verifier: the verifier POSTs the file's content as a note `body`, GETs
`/render`, and loads the served HTML in a **headless Chromium** launched by the
tests — the dialog caused by your payload must appear with no user action.

Do not rely on brute-force obfuscation only: the check requires the alert to fire
after `sanitizer.sanitize()` is applied.

---

## Constraints

- Work only under `/app`. Do not read or depend on `/tests` or `/solution`.
- `api.py` must start cleanly from a fresh process (`python3 /app/api.py 8039`)
  and must be importable (defining `canonical_header` and `app`, and NOT
  auto-starting the server on import).
- `schema.json`, `xss.html`, `api.py` must exist as real files.
- The render endpoint MUST apply `sanitizer.sanitize`.
- Deterministic integer `note` ids starting at 1, serving current-session state.