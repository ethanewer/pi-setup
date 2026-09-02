# Harborline — emit plan records against the planner service

The **Harborline capacity desk** holds a portfolio of provisioning *requests* in
memory and only accepts *plan records* through its HTTP API. You must write a
reusable client that **fetches every request and submits exactly one plan
record per request**, then commits. The verifier runs your client against fresh
hidden sessions it constructs, so it must obey the exact contract below on
**any** session — never hard-code the visible data.

## Provided files under `/app` (do NOT modify any of them)

- `/app/planner_service.py` — the planner HTTP service (read-only; the verifier
  runs fresh copies of it on other ports).
- `/app/planner/visible_case.json` — the visible session's requests.

Start the visible session yourself:

```
python3 /app/planner_service.py --serve --port 8731 \
    --case /app/planner/visible_case.json --out /tmp/visible_out.jsonl
```

## The service contract (JSON API on `127.0.0.1:<port>`)

- `GET /api/session` → `{"session", "total", "submitted", "status"}`
- `GET /api/requests?offset=O&limit=L` →
  `{"total", "offset", "limit", "requests": [...]}`.
  The server **clamps `limit` to at most 40** (default 25), so a portfolio
  larger than 40 requires multiple pages. Requests are returned in fixed
  portfolio order; page with `offset` until you hold all `total` of them.
  Each request is an object:
  ```json
  {"id": "...", "batch": "...", "tier": "...", "replicas": <int>,
   "storage_gb": <int>, "gpu": <bool, optional>}
  ```
  `tier` is one of `basic`, `standard`, `performance`; `replicas >= 1`;
  `storage_gb >= 0`; `gpu` may be absent (meaning `false`).
- `POST /api/plan` with **one** plan record as the JSON body. The record must
  deserialize with **exactly** this structure (any extra, missing, or
  misspelled key is rejected with `400` and consumed nothing):
  ```json
  {"id": "<request id>", "batch": "<the request's batch id>",
   "shape": {"vcpus": <int>, "memory_gib": <int>, "disk_gib": <int>}}
  ```
  - `id` must be a known request id that has **not** been planned yet.
    Submitting a second record for an id returns `409` and **permanently
    fails the session** (`status: "duplicate-plan"`) — an automatic fail.
  - `batch` must equal that request's `batch` value verbatim.
  - `shape` must carry exactly the keys `vcpus`, `memory_gib`, `disk_gib`
    with integer values matching the derivation below.
- `POST /api/commit` → the receipt. Committing consumes nothing; it succeeds
  only when **every** request id has received exactly one record:
  `{"session", "committed", "status", "submitted", "total", "missing",
  "records", "sha256"}`. On success `committed` is `true`,
  `status` is `"committed"`, and the service writes the plans file (one
  compact JSON record per line, in portfolio order) to its `--out` path.

## Shape derivation (per request)

- `vcpus = <per-tier base> * replicas + (8 if gpu else 0)`
  where the per-tier base is `basic: 1`, `standard: 2`, `performance: 4`.
- `memory_gib = <per-tier memory> * replicas`
  where the per-tier memory is `basic: 2`, `standard: 4`, `performance: 8`.
- `disk_gib` = the smallest multiple of 16 that is `>= storage_gb`,
  but never below 16 (so `storage_gb` of 0 or 1..16 all give 16, 17 gives 32).

## Deliverables (both required)

1. `/app/solve.py` — a reusable client, runnable as:
   ```
   python3 /app/solve.py --url http://127.0.0.1:<port> \
       --out <plans.jsonl path> [--receipt <out_json>]
   ```
   It must page through `GET /api/requests` until it holds all `total`
   requests, submit exactly one well-formed `POST /api/plan` record per
   request, then `POST /api/commit`, and write the plans file itself to the
   `--out` path (one compact JSON record per line, in portfolio order, each
   line ending with a newline, keys exactly `id`, `batch`, `shape` with
   `shape` keys exactly `vcpus`, `memory_gib`, `disk_gib`). If `--receipt` is
   given, write the commit receipt JSON there. It must work against ANY
   planner session following this contract (any port, any portfolio), so
   never hard-code the visible ids, batches, shapes, or port.

2. `/app/plans.jsonl` — the plans file your client produced **for the visible
   session**:
   ```
   python3 /app/solve.py --url http://127.0.0.1:8731 --out /app/plans.jsonl
   ```
   It must contain exactly one record per visible request, in portfolio order.

## Success check (what the grader enforces)

For every session (visible and hidden), ALL of the following must hold:

- the client exits 0 and writes a parseable plans file;
- the service-side committed file and your plans file both match the expected
  records exactly (same count, same order, same ids/batches/shapes, exact key
  structure — wrong keys break deserialization);
- the commit receipt reports `committed: true` / `status: "committed"` with
  zero missing records;
- no session ever entered `duplicate-plan` (never submit twice for one id).

## Edge cases the hidden sessions probe

- Portfolios of very different sizes, including a single-request session and
  sessions large enough to need three pages at the 40-request clamp.
- `gpu` absent vs explicitly `false` vs `true`; `storage_gb` of `0`, exact
  multiples of 16, and values just above a multiple of 16.
- Requests whose shape base differs per tier (a `performance` request is not a
  scaled `basic` one).
- A wrong record (extra key, missing key, string instead of int) is rejected
  — your client must never leave an id unplanned as a result.

## Constraints

- Work only under `/app`. Never read or depend on `/tests`, `/solution`, or
  any verifier data.
- Do not modify `/app/planner_service.py` or `/app/planner/*`.
- Standard library only; no network beyond `127.0.0.1` loopback HTTP.
