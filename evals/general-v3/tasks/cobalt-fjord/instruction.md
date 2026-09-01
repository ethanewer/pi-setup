# Compute derived statistics from an HTTP access log

You must build a reusable command-line program that parses an HTTP access log
in one of two documented line formats and writes a JSON report of **derived
statistics** computed over the successfully parsed records. The program must
work **on any input** conforming to the format below, not just on the provided
file — the grader runs it again on hidden inputs.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/access.log`. Python 3.12 is available as `python3`.
- **Do not modify `/app/access.log`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:

   ```
   python3 /app/solve.py <log_file> <output_json>
   ```

   It reads the log and writes the JSON statistics report to the given output
   path. Standard library only; no network access.

2. `/app/answer.json` — the report your program produces **when run on the
   provided `/app/access.log`**:
   ```
   python3 /app/solve.py /app/access.log /app/answer.json
   ```

## Input format

`log_file` is newline-separated text. Each line is in exactly one of two
categories:

- **Format A (space-separated, exactly 7 fields):**
  `TIMESTAMP CLIENT METHOD PATH STATUS BYTES LATENCYms`
  e.g. `2031-06-01T09:15:04Z 198.51.100.23 GET /api/items 200 512 41ms`
  - `TIMESTAMP` is `YYYY-MM-DDTHH:MM:SSZ` (UTC, literal `Z`).
  - `CLIENT` is a whitespace-free token (e.g. an IP address).
  - `METHOD` is all-caps `[A-Z]+` (e.g. `GET`, `POST`).
  - `PATH` is a whitespace-free token starting with `/`.
  - `STATUS` is exactly three digits with numeric value in `100..599`.
  - `BYTES` is a non-negative integer or a single `-` (unknown; counts as 0).
  - `LATENCYms` is a non-negative integer immediately followed by the literal
    `ms` (e.g. `41ms`).

- **Format B (pipe-separated, exactly 7 fields):**
  `TIMESTAMP|CLIENT|METHOD|PATH|STATUS|BYTES|LATENCY`
  e.g. `2031-06-01T09:15:07Z|198.51.100.23|POST|/api/orders|500|1024|188`
  - Each field may be surrounded by whitespace, which must be trimmed before
    validation. `BYTES` may be `-` or a non-negative integer; `LATENCY` is a
    plain non-negative integer (no `ms` suffix).

- **Malformed:** any line matching neither format exactly. This includes
  near-misses: wrong field count, bracketed timestamps in Format A, fractional
  latency like `41.5ms`, an `ms` suffix on a Format B line, extra tokens, a
  status of `999` or `099`, and empty/whitespace-only lines. Malformed lines
  are counted but otherwise ignored.

## Required output JSON

Exactly these top-level keys (contents compared by value):

```json
{
  "total_requests": 0,
  "malformed": 0,
  "status_classes": {"1xx": 0, "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0},
  "error_rate_pct": null,
  "avg_latency_ms": null,
  "p95_latency_ms": null,
  "bytes_total": 0,
  "unique_clients": 0,
  "endpoints": {},
  "health": "unknown"
}
```

Definitions (over successfully parsed lines only):

- `total_requests`: number of parsed lines.
- `malformed`: number of malformed lines.
- `status_classes`: counts per status class, where class is the status divided
  by 100 (`Nxx`). **All five keys are always present**, even when zero.
- `error_rate_pct`: `null` if `total_requests` is 0, otherwise
  `round(100.0 * (count_4xx + count_5xx) / total_requests, 2)` (a float, e.g.
  `30.0`).
- `avg_latency_ms`: `null` if there are no requests, otherwise the plain float
  mean of all latency values.
- `p95_latency_ms`: `null` if there are no requests, otherwise the 95th
  percentile of the latencies using **linear interpolation**: sort the
  latencies ascending, let `rank = 0.95 * (n - 1)`, let `lo = floor(rank)` and
  `hi = min(lo + 1, n - 1)`, and report
  `v[lo] + (rank - lo) * (v[hi] - v[lo])`. (For a single request this is that
  latency.)
- `bytes_total`: sum of BYTES over parsed lines, with `-` contributing 0.
- `unique_clients`: number of distinct CLIENT values among parsed lines.
- `endpoints`: one entry per distinct PATH among parsed lines:
  `"endpoints": {"<path>": {"count": <int>, "avg_ms": <float>}}` where
  `avg_ms` is the plain float mean of that path's latencies.
- `health`: derived from the **rounded** `error_rate_pct`:
  - `"unknown"` when `total_requests` is 0,
  - `"healthy"` when `error_rate_pct < 5.0`,
  - `"degraded"` when `5.0 <= error_rate_pct < 15.0`,
  - `"critical"` otherwise.

## Edge cases the grader probes

- Both formats interleaved in one file; whitespace-padded Format B fields.
- `-` bytes in either format; zero-byte responses.
- Malformed and near-valid lines anywhere (counted, ignored).
- Statuses outside `100..599` are malformed, not counted.
- An empty log (zero lines) and a log with only malformed lines.
- Exactly one request (`p95` equals its latency).
- Latency values that require interpolation at the 95th percentile.

## Constraints

- The verifier runs `/app/solve.py` unchanged on hidden inputs that follow the
  same format, so never hard-code to the provided file's contents or name.
- Deterministic; standard library only; no network access.
- Do not modify `/app/access.log`.
