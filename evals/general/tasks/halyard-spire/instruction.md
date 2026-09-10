# halyard-spire: ship a working monitoring pipeline for the orders service

You are the operator for an "orders" service. Prometheus is installed and a
small Python application is already deployed at `/app/app/orders_service.py`.
Your job is to make its metrics flow into a live Prometheus with the correct
metric *types*, and to prove you can read the result back.

## Environment

- Ubuntu 24.04. `prometheus` 2.45.3 (with `promtool`) is installed system-wide.
- Python 3.12 with the standard library is available as `python3`. No extra
  Python packages are installed and there is **no network**, so everything you
  write must use only the stdlib.
- `curl` and `jq` are installed. The `promtool` CLI is on `PATH` and has
  subcommands useful for checking configurations and rule files without
  starting a server (`promtool --help`).
- The shipped application is **read-only**; do not modify anything under
  `/app/app/` and do not modify `/app/docs/`. Everything else under `/app/`
  is yours to create.

## The shipped application

`/app/app/orders_service.py` listens on `127.0.0.1:8081`:

- `POST /orders` — body `{"sku": str, "qty": int (1..50), "urgent": bool}`.
  Returns `202` with an `order_id`. The service processes each order in the
  background; processing cost grows with `qty` and urgency, so individual
  orders take milliseconds to hundreds of milliseconds.
- `GET /api/monitor` — the machine-readable metrics state used by monitoring
  tooling. It returns JSON with these keys:

  | key | meaning |
  |---|---|
  | `orders_processed` | int, orders completed since service start |
  | `orders_failed` | int, rejected/errored orders |
  | `pending_orders` | int, orders currently inside the service |
  | `latency_window` | list of floats, latencies (ms) of recent orders |
  | `bytes_count` | int, number of order payloads accepted |
  | `bytes_sum` | float, total accepted payload bytes |

## Your deliverables

Create all four of these files under `/app/`:

### 1. `/app/exporter.py` — the metrics exporter

A standalone Python program that runs as `python3 /app/exporter.py`, polls the
application's monitor endpoint, and serves Prometheus metrics on
`127.0.0.1:9100` at the path `/metrics`. It must expose **exactly** these four
metrics, named and typed as follows:

| metric | type | value it must carry |
|---|---|---|
| `app_orders_processed_total` | counter | `orders_processed` |
| `app_orders_pending` | gauge | `pending_orders` |
| `app_latency_ms` | histogram | the `latency_window` distribution, milliseconds |
| `app_order_bytes` | summary | `bytes_count` / `bytes_sum` |

The histogram must be recorded by Prometheus as a **native histogram** with a
declared bucket structure: schema 0 (base-2 logarithmic buckets) with the upper
bounds `1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024` milliseconds. How the
exporter expresses all of this on the wire is up to you, but the ingestion
behaviour of this Prometheus build is not obvious — **read
`/app/docs/wire.md` in full before writing any code**. That document is the
authoritative specification of how metrics reach the store on this image,
including why a naive text response will not make the histogram survive as a
histogram.

### 2. `/app/prometheus.yml` — the Prometheus configuration

Configures the server to run with the exporter as scrape target and to load
your recording rules. The verifier will launch Prometheus exactly like this:

```
prometheus --config.file=/app/prometheus.yml \
           --storage.tsdb.path=/tmp/verify-prom/store \
           --enable-feature=native-histograms
```

So your config must (a) be valid under that invocation, (b) contain a scrape
job that polls `http://127.0.0.1:9100/metrics` and stores what it finds, and
(c) reference your rule file, plus be consistent with whatever intervals you
need. Prometheus listens on `127.0.0.1:9090`.

### 3. `/app/rules.yml` — recording rules

Define at least one recording rule group. A recording rule evaluates a PromQL
expression on a schedule and stores the result as a new queryable series. Use
it to materialise the per-second order processing rate so it can be queried
without recomputation. Validate your file with `promtool check rules /app/rules.yml`.

### 4. `/app/answers.json` — answer three questions with PromQL

Answer the following three questions about the live pipeline. For each, put a
single **PromQL expression** (a string) under the given key. An answer is
correct if, when the verifier evaluates it against the running Prometheus, its
value agrees with an independent measurement of the same quantity:

- `q1` — "At what rate are orders being processed right now?" Give one
  expression that evaluates to orders processed per second. (The recording
  rule you defined already computes this — a correct answer may simply name
  that series, or may compute the rate directly.)
- `q2` — "What is the mean order latency in milliseconds?" Give one expression
  that evaluates to the average of the latency histogram's samples.
- `q3` — "What is the mean payload size in bytes per order?" Give one
  expression from the summary's stored components. (Note how a SUMMARY metric
  surfaces in the store before writing this.)

Every answer will be evaluated **live**: if an expression fails to parse or
returns no data, that answer fails. You are expected to test by running the
pipeline yourself during your session, exactly as the verifier will: start the
app, start your exporter, start Prometheus with the command above, drive a few
orders with `curl`, and `curl` queries against
`http://127.0.0.1:9090/api/v1/query` to see how the PromQL type checker
behaves. Iterate until all four series exist, the recorded rule produces
values, and your three answers return the numbers you expect.

## Verifier behaviour (what it will check)

The verifier starts the app, starts your exporter, starts Prometheus from your
config with the exact command above, waits until the counter is in the store,
then:

1. Probes `http://127.0.0.1:9100/metrics` directly and decodes it: all four
   metrics must be present with the exact names above and the exact types
   (counter, gauge, histogram, summary); the histogram must declare schema 0
   with ten positive buckets through 1024 ms and internally consistent counts;
   the counter/gauge/summary values must track the app within a small lag.
2. Drives on the order of one to two hundred orders through the
   application over roughly 20–35 seconds (the exact load geometry is
   decided by the verifier, not by you), then queries the HTTP API with
   three PromQL expressions and asserts the returned values within
   tolerance of the measured processing rate:
   - `rate()` over the counter,
   - `rate()` over the histogram (per-bucket rates that sum to the rate),
   - the series your recording rule produces.
3. Evaluates your `answers.json` expressions live and compares each against an
   independent measurement of the same quantity (within a tolerance of a few
   tens of percent, relative to the measured value).

## Constraints

- Do not touch anything outside `/app/`. Do not modify the app or the docs.
- Your exporter and answers must not depend on the verifier's timings; only on
  live readings and documented behaviour.
- `cpus=1`; keep any thread usage minimal (a poller thread in the exporter is
  fine). Everything must run headless. The container has no systemd and no
  image entrypoint: you must start services yourself during your session, and
  the verifier starts them itself at evaluation time from your deliverables.