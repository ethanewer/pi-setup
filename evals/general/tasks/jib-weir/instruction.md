# jib-weir — Media Catalogue REST API (TypeScript, Express 4, zod)

Build, from scratch, a small production-shaped REST API for a media catalogue:
a TypeScript project under `/app` that serves four JSON endpoints with typed
request validation and a self-describing OpenAPI 3 document that is *generated
from the same zod schemas* that validate requests — not copied or hand-typed as
a fixed blob.

This is a "build it yourself" task: the only files that exist before you start
are the seed dataset, the vendored dependencies, and a short environment
readme. Everything else — the project layout, the zod error-mapping scheme, the
cursor encoding, the generator wiring — is your decision. The verifier judges
behaviour only: it boots your server with your `/app/start.sh` against several
datasets and exercises the contract below over real HTTP.

## Environment

- Node.js **22.23.2** (`node`, `npm` on `PATH`), Ubuntu base.
- There is **no network at trial time** and `npm` cannot reach a registry. Do
  **not** run `npm install`. The exact dependency tree you need is already
  installed at **`/app/node_modules`** (and its executables, e.g.
  `/app/node_modules/.bin/tsc`):
  - `express 4.22.1`, `zod 3.25.75`,
  - `@asteasolutions/zod-to-openapi 3.4.0` (converts zod schemas into an
    OpenAPI 3.0 document),
  - `typescript 5.9.3`, `@types/express 4.17.25`, `@types/node 22.20.1`.
- `python3` (3.11) is available and is a handy HTTP test client — there is no
  guarantee `curl` exists.
- `/app/data/media.json` is the seed dataset (see below); `/app/README-env.md`
  summarises all of this. Do not modify `/app/node_modules`.

## Deliverables

1. **`/app/start.sh`** — executable; builds your project and starts the server.
2. **`/app/openapi.json`** — the emitted OpenAPI 3.0 document (see the
   "OpenAPI document" section). It must be produced by running your build once,
   so the verifier and you are looking at the same artifact.

### `/app/start.sh` contract (exact)

```
bash /app/start.sh [PORT] [DATA_FILE]
```

- `PORT` — loopback TCP port, default `8780`.
- `DATA_FILE` — a JSON dataset file `{"items": [...]}`, default
  `/app/data/media.json`.
- The script must:
  1. build the TypeScript project (idempotently; a stale build must be
     refreshed) without network access;
  2. start the server bound to **`127.0.0.1`** on `PORT`, serving `DATA_FILE`,
     in the background;
  3. wait until the server answers `GET /health` with 200 (bounded loop);
  4. write the server's PID to **`/tmp/jib-weir-server.pid`**;
  5. print a single `READY port=<PORT> pid=<PID>` line and exit 0. Any failure
     prints diagnostics to stderr and exits non-zero.

The verifier calls this script repeatedly (once per dataset, always with a
fresh instance), waits for readiness, and later kills the recorded PID. Make it
idempotent: a previous instance recorded in the pidfile must be stopped by the
next invocation of `start.sh`.

Use ports **8780–8799** for your own manual testing; the verifier uses
9450–9453, which you should leave alone.

## Data and ordering

A dataset is `{"items": [ {item}, ... ]}` where each item has exactly the
fields the POST contract accepts (below) and **no** `id`. The server assigns
ids itself: items receive `1, 2, 3, …` in file order at startup, and each
accepted POST assigns the next fresh id (one above the largest id ever
assigned, so ids never collide). The response representation of an item is the
seed fields plus the assigned `id`:

```json
{
  "id": 17,
  "title": "pale lantern 03",
  "year": 1984,
  "rating": 61,
  "medium": "film",
  "tags": ["noir", "archival"]
}
```

## The API contract

Requests and responses are JSON. `Content-Type: application/json` is accepted
on bodies. There is no authentication; the server speaks plain HTTP on
loopback.

### Item validation rules (the single source of truth)

| field    | rule                                                        |
|----------|-------------------------------------------------------------|
| `title`  | string, 1–100 characters                                    |
| `year`   | integer, 1900–2100                                          |
| `rating` | integer, 0–100                                              |
| `medium` | one of `"film"`, `"series"`, `"documentary"`, `"short"`     |
| `tags`   | optional array of strings, 0–5 entries, each 1–40 chars     |

POST requires `title`, `year`, `rating`, `medium`; `tags` defaults to `[]` when
omitted. **Unknown top-level fields are rejected** in POST and PATCH bodies
(strict parsing; a body with a stray `"director"` key is invalid). PATCH bodies
are partial — any non-empty subset of the five fields — but must not contain
unknown fields either.

### Errors: the typed envelope

Every 4xx/5xx response is JSON with exactly this shape:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "human-readable summary",
    "details": [
      { "path": ["year"], "code": "too_small", "message": "…" },
      { "path": ["tags", 0], "code": "too_big", "message": "…" }
    ]
  }
}
```

- Validation failures (body, query, or path parameter): status **400**,
  `code: "validation_failed"`, and a non-empty `details` array where each entry
  has `path` (array of strings/numbers pointing at the offending field),
  `code`, and `message`. This is how your zod issues must surface — map the
  schema errors to `details`, don't swallow them into a bare message.
- Unknown resource: status **404**, `code: "not_found"`, no `details` key.
- A request whose body is not valid JSON must still get this JSON envelope
  with status **400** (Express's default HTML 400 handler is not acceptable).
- Non-integer or non-positive `id` path values (e.g. `abc`, `1.5`, `0`, `-3`):
  status **400**, `validation_failed`.

### Endpoints

**`GET /api/media`** — cursor-paginated list.

Query parameters:
- `limit` — integer 1–100, default 20. Out of range or non-integer → 400.
- `cursor` — optional, opaque. It is the `next_cursor` value from the previous
  page, sent back verbatim; a request without it starts at the beginning.

Response 200:

```json
{
  "items":       [ {item}, ... ],
  "next_cursor": "…",
  "total":       48
}
```

Semantics (the verifier checks each of these):
- items are ordered by **`year` ascending, ties broken by `id` ascending**;
- a page contains at most `limit` items;
- `next_cursor` is a URL-safe opaque string (only `[A-Za-z0-9._~-]`
  characters, optionally with trailing `=` padding) marking
  the *last delivered item*, or `null` when the last page has been reached;
- requesting the next page with that cursor yields exactly the following
  `limit` items with no gaps, no duplicates, and a constant `total`;
- `total` is the number of items currently in the catalogue.

**`POST /api/media`** — create. Body: the five-item contract above. 201:

```json
{ "item": { item-with-fresh-id } }
```

Invalid body → 400 envelope. The created item must be retrievable afterwards.

**`GET /api/media/:id`** — fetch one. 200:

```json
{ "item": {item} }
```

404 (`not_found`) when the id does not exist; 400 when `:id` is not a positive
integer.

**`PATCH /api/media/:id`** — partial update. Body: any non-empty subset of the
five item fields, no unknown fields. 200:

```json
{ "item": {item-after-patch} }
```

The change must be visible on a subsequent `GET /api/media/:id`. 400 for an
empty body, an unknown field, or a field that violates its rule; 404 for a
missing id; 400 for a non-integer id.

**`GET /health`** — 200 `{"status":"ok"}`. Used for readiness.

**`GET /openapi.json`** — 200, serves the delivered `/app/openapi.json`
document (byte-for-byte; re-serializing the identical document is tolerated,
a different document is not). The server reads the file at startup; no
regeneration at request time.

## The OpenAPI document

`/app/openapi.json` must be a valid OpenAPI **3.0.x** document that the server
also serves, generated by converting the zod schemas through the
`zod-to-openapi` generator (which requires the schemas' module to be wired to
it before the schemas are declared — see the package's API). The verifier
checks:

- `openapi` starts with `"3.0"`; `info.title` and `info.version` are non-empty;
- `paths` documents exactly these operations, including the responses the API
  actually returns:
  | path               | methods             | required documented responses        |
  |--------------------|---------------------|---------------------------------------|
  | `/api/media`       | `get`, `post`       | get: 200; post: 201 and 400           |
  | `/api/media/{id}`  | `get`, `patch`      | get: 200, 400, 404; patch: 200, 400, 404 |
- the POST `requestBody` schema (after resolving any `$ref`) is an object
  whose `required` is exactly `["title","year","rating","medium"]` and whose
  `properties` include all five fields;
- every `$ref` in the document resolves to an existing component;
- every documented non-parameterized `path` + `method` actually exists as a
  route on the running server (the verifier probes each and a documented-but-
  unimplemented route is a failure);
- at least one `.ts` source file under `/app` (outside `node_modules` / `dist`)
  imports the zod-to-openapi generator — the document must demonstrably be
  produced by converting your zod schemas, not transcribed by hand.

You may additionally document `/health` and `/openapi.json`; you are not
required to.

## How you are scored

The verifier (a) runs `/app/start.sh` against the visible dataset plus three
hidden datasets with different sizes and year-tie structures, each on a fresh
server instance, and asserts the full contract above — full pagination walks
(ordering, disjoint union, cursor semantics, `total`), fetch/404/400 behaviour,
validation 400s with per-field `details` for malformed POSTs and PATCHes
(including unknown fields and a non-JSON body), persistence of created and
patched items — and (b) validates `/app/openapi.json` and its served copy as
described. Any failure is a 0; everything passing is a 1.

Good luck. The fastest way to iterate is to write the server, run
`bash /app/start.sh`, and hammer it with `python3 -m http.client`-style probes
(or `node -e "fetch(...)"`) before you call it done.