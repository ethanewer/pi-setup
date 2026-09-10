# Cart — two-service storefront (tracing task)

`cart` is a small e-commerce read path split across two services that share a
message contract but, as shipped, none of the observability that production
applications need:

- `services/frontend/` — a Python (stdlib-only) storefront, the public edge.
- `services/backend/`  — a Go order service that owns order data.
- `services/collector/`— a Python span collector (the sink; **complete as
  shipped**, do not modify).
- `data/orders.json`   — the order catalog the backend serves.
- `up.sh`              — brings the whole stack up and polls readiness.

## Stack

| role      | process  | listen |
|-----------|----------|--------|
| collector | Python   | `127.0.0.1:9100` |
| backend   | Go       | `127.0.0.1:8100` |
| frontend  | Python   | `127.0.0.1:8000` |

`up.sh` builds the Go backend from source, launches all three processes in the
background, redirects frontend/backend stdout to `/app/.logs/frontend.jsonl`
and `/app/.logs/backend.jsonl`, and blocks until `/health` answers on all
three ports.

The frontend is the only service reachable from outside the stack; it calls
the backend directly (one-hop) for every order.

## HTTP surface

Frontend (`/`, the public edge):

| route | behaviour |
|-------|-----------|
| `GET /health` | `200` |
| `GET /order/<id>` | resolves one order via the backend; mirrors the backend's status |
| `GET /batch/<a>/<b>` | fans out to the backend for `<a>` and `<b>` **concurrently** and returns `[orderA, orderB]` with `200` when both succeed |

Backend (`/`, internal only):

| route | behaviour |
|-------|-----------|
| `GET /health` | `200` |
| `GET /order/<id>` | `200` + order JSON when `<id>` is in the catalog; `404` for unknown ids; `500` for the id `OR-LOST` (a poisoned record whose recompute fails) |

## Observability contract (the graded behaviour)

A request that enters the frontend must be observable end to end **and** the
grader must be able to reconstruct it from emitted data alone. Concretely:

1. **W3C traceparent.** The frontend must accept a `traceparent` request
   header, honour it, and propagate it. The wire format is the standard
   `00-<trace-id:32 lower-hex>-<span-id:16 lower-hex>-<flags:2>`. When no
   header is present the frontend must mint its own trace id. The frontend
   must forward a valid `traceparent` carrying the **same** trace id to the
   backend for every backend call, so that both services' observations for a
   single client request share one trace id.

2. **Structured JSON logs with a consistent correlation field.** Every log
   line the frontend and backend write for a traced request is one JSON object
   on its own line, and every such line carries the correlation field
   `trace_id` equal to that request's trace id. Lines are appended to
   `/app/.logs/frontend.jsonl` and `/app/.logs/backend.jsonl` respectively
   (the collector is excluded). The correlation key is **`trace_id`** — keep
   the name identical across both services.

3. **Spans emitted to the collector.** Each service records a span for each
   request it handles and POSTs it to the collector at `127.0.0.1:9100/span`
   (a span per service per request — one frontend span and, for each backend
   call, one backend span). Span records are JSON objects with at least:

   ```
   service          "frontend" | "backend"
   name             a stable per-route name
   trace_id         32 lower-hex
   span_id          16 lower-hex
   parent_span_id   16 lower-hex, or all zeros for a root
   kind             "server"
   start_ms         int epoch millis
   end_ms           int epoch millis
   status           int HTTP status observed by that service
   error            bool  (true when status >= 500)
   ```

   The collected spans for one trace must form a **single rooted tree**: the
   frontend span is the root (its `parent_span_id` is the caller's span id,
   or zeros when the frontend minted the trace), and every backend span's
   `parent_span_id` equals the frontend root span's `span_id` (the frontend is
   the sole caller of the backend). A fan-out therefore yields one frontend
   root span plus one backend span per concurrent child call, all in one tree.

4. **Failure visibility.** When the backend returns `500` (the `OR-LOST`
   id), the frontend must surface that failure to the client (same `500`
   status), record an `error:true` span for it, and log it with the trace id.
   Correct status passthrough is part of the contract.

The collector is a sink only: do not change ports, the POST `/span` shape, or
`/spans` semantics, and do not persist spans to a file the grader cannot read.

The grader starts everything with `up.sh` and then drives its own request
patterns (fresh trace ids) through the frontend, so the stack must be idle
and correct when `up.sh` returns.
