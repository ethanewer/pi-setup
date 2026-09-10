# floodgate

In-memory rate limiting with pluggable accounting strategies.

`floodgate` is a small library crate. A `FloodGate` is constructed from a
[`core::Config`] and evaluates one request per call:

```rust
use floodgate::core::{Config, Verdict};
use floodgate::FloodGate;

let mut gate = FloodGate::new(&Config::defaults());
match gate.check("alice", 1, 1_700_000_000_000) {
    Verdict::Admit => { /* request allowed */ }
    Verdict::Defer { retry_after_ms } => { /* slow down; may retry after retry_after_ms */ }
}
```

## Build

The crate ships three accounting strategies. Optional strategies are selected
with Cargo features:

| Feature combination                        | Active strategy             |
|--------------------------------------------|-----------------------------|
| (default, no features)                     | fixed-window counter        |
| `--features sliding`                       | sliding-window              |
| `--features bucket`                        | token bucket                |
| `--features sliding,bucket`                | combined sliding + bucket   |

Every combination above is expected to build and to pass the full test suite.

## Configuration

[`core::Config`] has four fields; each strategy reads only the fields it needs.

| Field       | Meaning                                                        | Read by      |
|-------------|----------------------------------------------------------------|--------------|
| `capacity`  | burst allowance in units                                       | sliding, bucket |
| `window_ms` | trailing/max window length in milliseconds (clamped up to 1)   | counter, sliding |
| `refill_ms` | milliseconds to earn one unit of burst (clamped up to 1)       | bucket       |
| `quota`     | units admitted per fixed window                                | counter      |

All arithmetic inside the crate is clamped so no path can overflow a `u64`
even in a debug build, and a request with `qty == 0` is always admitted and
never recorded by any strategy.

## Strategy contracts

### Counter (no features)

- Time is divided into fixed windows of `window_ms`, aligned to epoch zero; a
  request at `now_ms` belongs to window `now - now % window_ms`.
- Every check is recorded: the counter counts all probes, admitted or not.
- A request is admitted iff the recorded total for the current window,
  including this request, is at most `quota`.
- On a denial the retry delay is the time until the current window ends:
  `window_ms - (now - aligned_window_start)`.

### Sliding (`sliding`)

- A request for a key is admitted iff the sum of quantities admitted for that
  key within the trailing `window_ms`, plus this request's quantity, is at
  most `capacity`.
- An admitted request is recorded at the current timestamp. An event leaves
  the window when `now - event_ts >= window_ms`; an event recorded exactly
  `window_ms` ago no longer counts.
- Only admitted requests are recorded. A denied request changes no state, so
  repeated probes of a full window all report the same retry delay.
- Timestamps observed for a key are monotonic: `now_ms` smaller than the key's
  latest observed timestamp is clamped up to it.
- On a denial, `next_ok_ms` is the time until the oldest recorded event
  leaves the window: `window_ms - (now - oldest_ts)`. When nothing is
  recorded for the key (possible only when `qty` exceeds `capacity` on its
  own) the delay is `0`.

### Bucket (`bucket`)

- Each key starts at `capacity` tokens and accrues one token per `refill_ms`
  of elapsed time, never exceeding `capacity`.
- A request is granted iff `qty <= tokens`; a granted request consumes `qty`
  tokens and stamps the refill clock with the current time. A denied request
  consumes nothing and changes no state.
- Timestamps observed for a key are monotonic as above.
- On a denial, `ready_ms` is the time needed to accrue the missing tokens:
  `(qty - tokens) * refill_ms`.

### Combined (`sliding,bucket`)

When both optional features are enabled the gate consults **both** strategies
for every request:

- The request is admitted **only when both strategies admit** it.
- On a denial, the retry delay is the **larger** of the two strategies'
  individual retry delays, where a strategy that admits contributes zero. This
  is the earliest instant at which a retry could plausibly succeed: the
  request stays blocked until the *last* of the two constraints releases.
- A strategy that admits contributes no delay, even though it may have
  recorded the request. The combined gate is never more permissive than the
  stricter strategy.

## Tests

`cargo test` runs the unit suite for the feature combination the crate was
compiled with:

- `tests/gates.rs`        – counter strategy (runs in every combination)
- `tests/single.rs`       – sliding-only and bucket-only behaviour
- `tests/dual.rs`         – combined behaviour (both features enabled)