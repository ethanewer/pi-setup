# Quartz Haven — bulk portfolio ingestion service that scales

Quartz Haven's back-office runs an in-house **portfolio ingestion service**.
Index funds push their full holdings as bulk uploads: a single request can
carry **ten thousand or more assets**, and downstream systems then issue
thousands of point lookups against it. The previous implementation died at
that scale (memory blow-up and O(n^2) duplicate scans, then crashes). You are
rebuilding it. Everything is standard-library Python 3.12 — no third-party
packages are installed or needed.

## Environment

- Working directory `/app`. It already contains
  `/app/visible_portfolio.json` — a small (300-asset) sample upload shaped
  exactly like the real ones.
- Do **not** modify `/app/visible_portfolio.json`.
- Do not read or depend on `/tests` or `/solution`.

## Deliverables (both required)

1. **`/app/api.py`** — the service. It must expose a WSGI callable named
   `application(environ, start_response)` and, when run as
   `python3 /app/api.py <port>`, serve the same app on `127.0.0.1:<port>`.
   Importing the module must NOT start a server.
2. **`/app/summary.json`** — the portfolio summary your service returns after
   ingesting `/app/visible_portfolio.json` (ingest it as one bulk request,
   then `GET /api/v1/portfolio/summary` and save the JSON body verbatim).

## HTTP contract (all bodies are JSON)

### `POST /api/v1/assets/bulk`

Request body: `{"assets": [ <asset>, ... ]}` where each **asset** is an object
with:

- `"asset_id"`: non-empty string (the primary key),
- `"ticker"`: non-empty string (store it **uppercased**),
- `"quantity"`: a number (`int` or `float`, not `bool`) with value `>= 0`,
- `"price"`: a number (`int` or `float`, not `bool`) with value `>= 0`.

Extra keys inside an asset are ignored. Validation is **all-or-nothing**:
if *any* asset in the request is invalid (wrong/missing key, wrong type,
negative value, non-string `asset_id`/`ticker`), duplicates the `asset_id` of
an asset already stored or of another asset in the same request, or the
`assets` array is empty/absent — respond `400` with
`{"error": {"code": "bad_request"}}` and store **nothing** from that request.
On success respond `201` with `{"accepted": <n>, "total": <m>}` where `n` is
the number accepted by this request and `m` is the cumulative number of stored
assets.

### `GET /api/v1/assets/<asset_id>`

`200` with the stored record `{"asset_id", "ticker", "quantity", "price"}`
(ticker uppercased), or `404` with `{"error": {"code": "not_found"}}` for an
unknown id.

### `GET /api/v1/portfolio/summary`

`200` with:

```json
{
  "count": <int total stored assets>,
  "total_value": <sum over assets of quantity * price>,
  "by_ticker": { "<TICKER>": {"count": <int>, "value": <float>}, ... }
}
```

### `GET /api/v1/health`

`200` with `{"status": "ok"}` (liveness probe).

## Scaling requirements (probed by the grader)

- A single bulk request with **10,000 assets** must be accepted correctly,
  and the service must remain correct afterwards (lookups, summary).
- Thousands of point lookups must each return the right record without the
  service slowing down unacceptably; repeated ingest batches must stay
  O(1) per duplicate check, not re-scan history per asset.
- The verifier enforces per-case wall-clock limits (tens of seconds); a
  correct dict/index-based implementation finishes in a few seconds.
- Nothing may crash, leak unbounded memory, or lose data across batches.

## Numeric comparison

Floats in summaries are compared by the verifier with a small absolute
tolerance (0.01), so ordinary float arithmetic is fine.

## Constraints

- Standard library only; no network access at verify time (the verifier
  drives your WSGI callable directly and also starts it once on a local port).
- The verifier runs your code unchanged on hidden inputs (fresh bulk
  payloads, batch sequences, lookups, invalid requests). Implement the
  general contract — do not hard-code the visible fixture.
