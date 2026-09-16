# culvert-keel: drive a registration service

You are handed an empty `/app` (plus a read-only fixture under `/app/config`)
and must author, **from scratch**, a small HTTP service in Go 1.22. There is
**no network access** in this container, and no Go module cache is pre-seeded,
so the service must be implemented using **only the Go standard library** —
nothing can be `go get`-ed at build time or run time. The installed toolchain
is `go1.22.2` with the classic standard library (`net`, `encoding/json`,
`crypto/rand`, `time`, `bufio`, `sync`, ... all available).

The service is a JSON "registry" API protected by a middleware chain:
request-ID propagation, bearer-token authentication against a local key file,
per-principal token-bucket rate limiting, and structured JSON logging — in
front of two JSON endpoints.

## Deliverables

You must create exactly these files:

1. `/app/server/main.go` — the Go implementation of the whole service.
2. `/app/run_server.sh` — an executable shell script that builds (if
   necessary) and launches the service in the background. The verifier starts
   the server through this script, so its behaviour below is a hard contract.

## The launcher: `/app/run_server.sh`

Usage: `bash /app/run_server.sh CONFIG_DIR PORT`

- `CONFIG_DIR` is the directory of a config fixture (see below); `PORT` is the
  TCP port to listen on (e.g. `18080`).
- The script must: compile the Go program at `/app/server/main.go` (if the
  binary is missing or stale) using `go build` from `/app/server`; launch the
  server in the **background**; write the server's PID to `/app/server.pid`;
  and return **immediately** — it must not block while the server runs.
- The server's own stdout/stderr should go to `/app/server.out.log`.
- The verifier will invoke it as `bash /app/run_server.sh /tests/hidden/<case> <port>`
  and then poll `GET /healthz` until the service answers (timeout 30s).

During development you can start and stop the server yourself, e.g.
`bash /app/run_server.sh /app/config 18080`, then
`curl -s http://127.0.0.1:18080/healthz`.

## Config fixture

Every fixture directory contains three files:

- **`server.json`** — service settings:

```json
{
  "host": "127.0.0.1",
  "tokens_file": "keys.txt",
  "entries_file": "entries.json",
  "log_file": "/app/server.log",
  "rate_limit": { "capacity": 6, "refill_per_sec": 2 }
}
```

  `tokens_file` and `entries_file` are relative to the config directory;
  `log_file` is an absolute path. `rate_limit.capacity` is an integer ≥ 1,
  `rate_limit.refill_per_sec` is a positive number of tokens refilled per
  second. Every fixture may set different values.

- **`keys.txt`** — one bearer token per line, format `token=principal`.
  Blank lines and lines starting with `#` are ignored. Tokens are unique;
  principals are not necessarily unique. Leading/trailing whitespace around
  each field is trimmed. Malformed lines (no `=`, empty token or principal)
  are skipped.

- **`entries.json`** — the registry's initial rows:

```json
{ "entries": [ { "name": "keel", "value": "oak" }, ... ] }
```

  The list may be empty. Order is significant: the registry serves rows in
  file order, then any rows added via POST, in the order they were added.

## The HTTP contract

The service must speak HTTP/1.1 over TCP, listening on
`<host>:<port>` from the config (host is the first CLI argument's fixture
`host`, port is the second CLI argument). Every response must include exactly
`Content-Type: application/json` and a `Content-Length`, and the service may
close the connection after each response (`Connection: close`).

### Endpoints

| Method | Path              | Success                  | Notes |
|--------|-------------------|--------------------------|-------|
| GET    | `/healthz`        | `200 {"ok":true}`        | **No** auth, **no** rate limit. Readiness probe. |
| GET    | `/api/v1/registry`| `200 {"principal":"<p>","entries":[...]}` | Requires auth + rate limit. |
| POST   | `/api/v1/registry`| `201 {"added":{"name":...,"value":...},"principal":"<p>"}` | Requires auth + rate limit. Body `{"name":"...","value":"..."}`; duplicate `name` → `409 {"error":"duplicate_name"}`; unparseable body or empty `name` → `400 {"error":"bad_json"}`. |

Request bodies are read exactly per `Content-Length` (bounded at 1 MiB).
Unknown query strings are ignored.

Other paths/methods return JSON errors: unknown `/api/*` path →
`404 {"error":"not_found"}`; any other path → `404 {"error":"not_found"}`;
supported path with unsupported method → `405 {"error":"method_not_allowed"}`.

### Middleware chain (applied in this order, to every `/api/*` request)

1. **Request-ID.** Read the `X-Request-ID` request header. If it is present,
   non-empty, printable ASCII, and at most 128 characters, use it verbatim;
   otherwise generate a fresh UUID v4. Every response carries the effective
   request ID in an `X-Request-ID` response header, and every log record for
   that request carries the same value (this is how a request is correlated
   across the stack — "propagation").

2. **Bearer authentication.** Read `Authorization`. Only the form
   `Authorization: Bearer <token>` (case-insensitive scheme) is accepted, and
   `<token>` must be a key in the fixture's `keys.txt`. Missing, malformed,
   or unknown tokens → `401 {"error":"unauthorized"}` with a
   `WWW-Authenticate: Bearer` response header. Authentication happens
   **before** rate limiting: an unknown token always gets `401`, never `429`.

3. **Per-principal token-bucket rate limiting.** Each principal (resolved
   from the token) has its own bucket with `capacity` tokens, refilled at
   `refill_per_sec` tokens per second, capped at `capacity`. Every
   authenticated request consumes one token; when no token is available the
   response is `429 {"error":"rate_limited"}` with a `Retry-After` response
   header (an integer number of seconds until the bucket can serve again).
   Buckets are strictly per-principal: exhausting one principal must not
   throttle any other principal, and `/healthz` never consumes a token.

4. **Structured JSON logging.** After every request (including `/healthz`,
   including errors), append exactly one JSON object per line to the file
   named by `log_file`:

```json
{"ts":1788939000,"request_id":"...","method":"GET","path":"/api/v1/registry","status":200,"principal":"alice"}
```

   Required keys: `ts` (integer unix seconds), `request_id` (string,
   non-empty), `method` (string), `path` (string, path only, no query),
   `status` (int), `principal` (string for authenticated requests, `null`
   otherwise). One object per line, ending with a newline.

### Registry state

The registry is in-memory state that persists across requests for the life of
the process: `GET` returns the fixture rows plus rows added by `POST` (in
order), and a `POST` for a name that already exists (fixture or added) is a
`409`. A restart reloads the fixture.

## Constraints

- Go standard library only; no third-party modules, no vendored code, no
  generated stubs. `go build` (single-file build, no `go.mod` required) must
  succeed with the network disabled.
- The service must read **everything** from the config fixture at startup —
  host, key file, entries file, log file, and rate-limit parameters. No part
  of the behaviour may be hard-coded, because the verifier runs the service
  against fresh fixtures under `/tests/hidden` that carry different keys,
  principals, limits, and data.
- Do not modify anything under `/app/config` (it is the visible fixture only)
  and do not create unrelated files that interfere with the fixtures.

## What the verifier will do

For each of three hidden fixture directories (different tokens/principals,
different token-bucket capacity/refill, different entries — including an
empty registry), it will:

- run `bash /app/run_server.sh <fixture> <port>` after truncating the
  configured log file, and poll `GET /healthz` until `200`;
- drive the contract: echoed/generated request IDs, authenticated
  `GET`/`POST` (including `201`/`400`/`409`/`404`/`405` bodies), `401` paths
  for missing/unknown/malformed credentials, a **measured burst** that must
  produce `429` with `Retry-After` while a different principal stays
  unthrottled, recovery of a throttled principal after its bucket refills,
  and finally verify that every line of the JSON log is well-formed and that
  the request IDs, statuses, and principals recorded match the requests it
  made.

Make the implementation robust and deterministic: no sleeps in request
handling, no dependence on wall-clock timing other than the token bucket's
own refill math, and correct JSON escaping for values that contain unicode or
spaces.