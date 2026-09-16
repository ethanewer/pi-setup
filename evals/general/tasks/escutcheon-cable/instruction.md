# escutcheon-cable: add end-to-end traceability to a two-service storefront

`/app` holds a small e-commerce read path split across two services under
`/app` (read `/app/README.md` — it is the contract). The system **works**: you
can fetch orders through the public edge, fan out to several orders at once,
and see failures propagate. What it is **missing** is every piece of
observability a production team needs: no W3C trace context is propagated
between the services, the logs are plain text rather than structured JSON, and
no spans are recorded anywhere. Your job is to add that observability so that a
single client request is fully reconstructible end to end from emitted data.

## Environment

- OS: Ubuntu 24.04. Installed: **Go 1.22** (`go` on PATH), **Python 3**,
  **curl**. No third-party Python packages — use the standard library only.
  No external network after the image is built; everything is loopback.
- `/app/up.sh` — the deliverable that starts the whole stack (builds the Go
  service from source, launches all processes, redirects frontend/backend
  stdout to the structured-log files, and polls readiness). **You may adjust
  it if you need to**, but the public contract below must hold.
- `/app/services/collector/` is the span sink. It is **complete and must not
  be modified** (do not change its ports, its `POST /span` shape, or its
  `/spans` semantics — but you *must* export spans to it).

## The stack

| role      | process | listen            |
|-----------|---------|-------------------|
| collector | Python  | `127.0.0.1:9100`  |
| backend   | Go      | `127.0.0.1:8100`  |
| frontend  | Python  | `127.0.0.1:8000`  |

The frontend is the **only** service reachable from outside the stack; it calls
the backend directly (one hop) for every order. `GET /order/<id>` mirrors the
backend's status. `GET /batch/<a>/<b>` fans out to the backend for both ids
**concurrently** and returns `[orderA, orderB]` with `200` when both succeed.

## Required behaviour (the graded contract)

1. **W3C traceparent propagation.** The frontend accepts a `traceparent`
   request header and honours it; when none is present it mints its own trace
   id. For every backend call the frontend forwards a valid `traceparent`
   carrying the **same** trace id, so both services' observations of one client
   request share a single trace id. Format: `00-<32 lower-hex>-<16
   lower-hex>-<2>`.

2. **Structured JSON logs.** Frontend and backend each write newline-delimited
   JSON to `/app/.logs/frontend.jsonl` and `/app/.logs/backend.jsonl`
   respectively. Every log line a service writes **for a traced request** is a
   single JSON object carrying a correlation field literally named **`trace_id`**
   equal to that request's trace id (the same key name in both services).

3. **Spans to the collector.** Each service POSTs one span per request it
   handles to `127.0.0.1:9100/span` (one frontend span and, per backend call,
   one backend span). A span is a JSON object with at least:
   `service`, `name`, `trace_id` (32 lower-hex), `span_id` (16 lower-hex),
   `parent_span_id` (16 lower-hex, all-zeros for a root), `kind`, `start_ms`,
   `end_ms`, `status`, `error`. The spans for one trace must form a **single
   rooted tree**: the frontend span is the root (parent = the caller's span
   id, or zeros when the frontend minted the trace) and every backend span's
   parent is the frontend root's span id. A fan-out therefore produces one
   frontend root plus one backend span per concurrent child.

4. **Failures are visible and propagated.** When the backend answers `500`
   (use the id `OR-LOST` to trigger it), the frontend must return `500` to the
   client, record an `error:true` span, and log it with the trace id.

The grader starts everything with the deliverable `/app/up.sh`, then drives
its own request patterns (single order, a concurrent fan-out, and a failing
request) through the frontend with fresh trace ids, parses the collected
spans, and checks the log files. It must be able to reconstruct each request
from the spans and logs alone — do not return data to the grader that is
inconsistent with the emitted trace.

## Deliverable

- `/app/up.sh` — a script that brings the full stack up as described and
  leaves it running and healthy at the end of your session.

## Constraints

- Do not modify anything under `/app/services/collector/`.
- All ports above are fixed. Use stdlib tools only (no new dependencies).
- No external network; keep everything on loopback.
