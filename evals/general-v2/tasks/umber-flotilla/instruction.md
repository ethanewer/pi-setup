# Umber Flotilla — fund-administration portfolio ingest service

You are the platform engineer for **Umber Flotilla**, an internal
fund-administration tool. Operations staff upload whole portfolios as one JSON
document (fleets routinely hold **thousands of assets**), and downstream
dashboards read a per-portfolio summary. You must deliver a small HTTP service
plus one generated report.

Everything you produce lands in `/app`. A verifier later starts **your**
service in fresh processes and replays hidden portfolios against it, so
nothing may depend on your current session. Python 3.12 with Flask is
available (install nothing; `import flask` works).

Read this whole contract before starting.

## Deliverables (both required)

1. **`/app/service.py`** — the Flask service. It must be runnable as
   `python3 /app/service.py [PORT]` (default port `8100` when omitted) and
   must also be importable without side effects (exposing a WSGI `app`).
2. **`/app/summary.json`** — the summary your service returns **for the
   shipped visible portfolio** `/app/portfolio_visible.json` (see "How to
   produce /app/summary.json"). Do not modify `/app/portfolio_visible.json`.

## HTTP contract

All request/response bodies are JSON. Error responses are structured:
`{"error": {"code": "<code>", "message": "<text>"}}` with codes `bad_request`
and `not_found`.

### `GET /api/v1/health`
`200` with body `{"status": "ok"}`.

### `POST /api/v1/portfolios`
Request body: `{"id": <string>, "assets": [<asset>, ...]}` where each asset is
`{"id": <string>, "sector": <string>, "quantity": <number>, "unit_price":
<number>}`.

Validation — return **HTTP 400** (`bad_request`) when any of these holds:
* the request body is not a JSON object;
* `id` is missing, or not a non-empty string;
* `assets` is missing, or not a list;
* any asset is not a JSON object;
* any asset is missing one of the four keys;
* an asset `id` or `sector` is not a non-empty string;
* an asset `quantity` or `unit_price` is not a JSON number (`int`/`float`).
  Booleans are **not** numbers. Non-finite values (`NaN`, `Infinity`) are
  rejected too;
* two assets in the same request share the same `id` (duplicates rejected).

On success (**HTTP 201**): store the portfolio (re-POSTing an existing id
replaces it) and return `{"id": "<id>", "asset_count": <n>}`.

Portfolios must be handled in **constant memory per asset and linear total
time** — the verifier replays a 6,000-asset portfolio, so per-request
recomputation over quadratic loops or per-asset file I/O will fail the run.

### `GET /api/v1/portfolios`
`200` with `{"count": <n>, "portfolios": [{"id", "asset_count"}, ...]}` in
insertion order (a replaced portfolio keeps its original position).

### `GET /api/v1/portfolios/<id>/summary`
* unknown id → **HTTP 404** `{"error": {"code": "not_found", "id": "<id>",
  "message": "..."}}`.
* known id → **HTTP 200** with exactly this shape:

```json
{
  "id": "<id>",
  "asset_count": <int>,
  "total_value": <float>,
  "sectors": {"<sector>": {"count": <int>, "value": <float>, "weight": <float>}},
  "top": [{"id": "<asset id>", "value": <float>}, ...]
}
```

Semantics (deterministic; the verifier compares floats to 4 decimal places):
* per-asset value = `quantity * unit_price` (a plain float multiply);
* `total_value` = the sum of asset values **in file (upload) order**;
* sector `value` = sum of that sector's asset values in upload order;
  sector `count` = number of that sector's assets;
* sector `weight` = `value / total_value`, except when `total_value == 0`
  (possible when all quantities are zero or values cancel): every weight is
  `0.0`. Weights may be negative (short positions are allowed via negative
  quantities);
* `top` = the **at most 10** assets with the largest value, descending; ties
  broken by asset `id` ascending (plain string comparison). Fewer than 10
  assets → all of them, same ordering. An empty portfolio → `[]`.

An empty `assets` list is **valid** (201, `asset_count` 0, `total_value` 0.0,
empty `sectors` and `top`).

### Other paths/methods
Return `404` with `{"error": {"code": "not_found", "message": "..."}}`.

## How to produce `/app/summary.json`

Start your service, POST the contents of `/app/portfolio_visible.json` to
`/api/v1/portfolios`, then GET
`/api/v1/portfolios/visible-fleet/summary` and write the response JSON
(verbatim, pretty or compact — content is what matters) to
`/app/summary.json`. The verifier compares this file against its own
reference for the same fixture and also re-drives your live service.

## Constraints

- Work only under `/app`. Do not read or depend on `/tests` or `/solution`.
- Do not modify `/app/portfolio_visible.json`.
- Deterministic behavior only; no network access beyond localhost.
- The verifier starts your service as `python3 /app/service.py <port>` on a
  fresh process per check round; it must be listening within 15 seconds.
