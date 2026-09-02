# Cinder Reach — HTTP access-log statistics

`/app/access.log` is an HTTP server access log in a fixed "extended combined"
format. Build a small, reusable Python program that parses any such log and
emits a JSON report of derived statistics. The verifier will run your program
again on other logs matching the same contract, so it must be general.

## Deliverables

Write exactly two artifacts under `/app`:

1. **`/app/solve.py`** — a runnable Python 3 program. Command-line contract:

   ```
   python3 /app/solve.py [INPUT.log [OUTPUT.json]]
   ```

   Default input is `/app/access.log`; default output is `/app/stats.json`.

2. **`/app/stats.json`** — the JSON report your program produces for the
   shipped `/app/access.log` (run your `solve.py` yourself to generate it).

## Input line contract (must hold exactly)

Every non-blank line must match this shape exactly:

```
<ip> - <user> [<timestamp>] "<METHOD> <path> HTTP/<x.y>" <status> <bytes> <latency_ms> "<referer>"
```

- `<ip>`: any non-whitespace token (the client).
- The literal `-` separates ip and user; `<user>` is any non-whitespace token
  (frequently `-`).
- `<timestamp>`: anything up to the matching `]`, e.g. `07/Jan/2025:09:12:03 +0000`.
- The request is quoted: `<METHOD>` is uppercase `[A-Z]+`, `<path>` is any
  non-whitespace token, protocol is literally `HTTP/` followed by digits.digits.
- `<status>`: exactly three digits with first digit 1-5 (100..599).
- `<bytes>`: a non-negative integer, or a single `-` meaning "no body" (count 0).
- `<latency_ms>`: a non-negative integer (response time in milliseconds).
- `<referer>`: any text without a double quote, inside double quotes (frequently `-`).

Lines that do not match this shape exactly are **malformed**. Empty or
whitespace-only lines are **skipped silently** (they are NOT counted as
malformed). A malformed line contributes nothing to any statistic.

## Report computation (exact)

Over the valid lines only:

1. **`total_requests`**: number of valid lines.
2. **`malformed`**: number of malformed lines (blank lines excluded).
3. **`status_classes`**: object with exactly the five keys `1xx`, `2xx`, `3xx`,
   `4xx`, `5xx` (always present, in that order) counting valid lines per class.
4. **`error_rate`**: (`4xx` + `5xx`) / `total_requests`, rounded to 4 decimal
   places. `null` when `total_requests` is 0.
5. **`avg_latency_ms`**: mean of all latency values, rounded to 4 decimal
   places. `null` when `total_requests` is 0.
6. **`p95_latency_ms`**: the 95th percentile of the latency values, computed as
   follows: sort the latencies ascending, let `i = 0.95 * (n - 1)`; if `i` is an
   integer take `sorted[i]`, otherwise linearly interpolate between
   `sorted[floor(i)]` and `sorted[ceil(i)]`. Round the result to 4 decimal
   places. `null` when `total_requests` is 0.
7. **`bytes_total`**: sum of the byte counts (`-` counts as 0).
8. **`top_client`**: the `<ip>` with the most valid requests. Ties are broken by
   choosing the lexicographically smallest ip. `null` when `total_requests` is 0.

## Output format (exact)

`/app/stats.json` must be JSON with exactly these keys, in this order:

```json
{
  "total_requests": <int>,
  "malformed": <int>,
  "status_classes": {"1xx": <int>, "2xx": <int>, "3xx": <int>, "4xx": <int>, "5xx": <int>},
  "error_rate": <number or null>,
  "avg_latency_ms": <number or null>,
  "p95_latency_ms": <number or null>,
  "bytes_total": <int>,
  "top_client": "<ip>" or null
}
```

`null` is written as JSON null, never as a string.

## Edge cases the hidden checks probe

Make sure your program handles all of the following:

- An **empty log file** (or only blank lines): totals 0, all nullable fields
  `null`, all status classes 0.
- Malformed variants: truncated lines, a status of `999` (first digit not 1-5),
  non-numeric latency or bytes, a missing quoted referer, wrong method case
  (lowercase methods are malformed).
- Byte field `-` mixed with numeric byte counts.
- Ties for `top_client` (must pick the lexicographically smallest ip).
- An odd and an even number of latencies (p95 interpolation in both cases).
- All requests failing (error rate exactly 1.0) and none failing (0.0).

## Rules

- Do **not** modify or delete `/app/access.log`, and make no other changes to
  the machine other than creating the two deliverables.
- The program must read from the input path given on the command line (or the
  default) and write JSON to the requested output path; it must not hard-code
  anything about this specific file beyond the documented contract.
- Output must be deterministic and require **no network access**.
