# thwart-quarry: a live, concurrency-safe Redis cache layer

You are building a small cache layer in front of a slow backend data source,
backed by a **live Redis 7 server** inside the trial container. The environment
is Ubuntu 24.04 with `redis-server` 7.0.15 and `redis-cli` installed, plus
Python 3.12.3 with the `redis` client library (redis-py 7.0.1) preinstalled.
No other third-party packages are installed. Use only the Python standard
library plus `redis`; a `redis.Redis` client is thread-safe to share between
threads.

There is no systemd and no container ENTRYPOINT: the agent (you, while testing)
and the verifier both bring redis up themselves, per port, with a **start
script that is one of your deliverables**.

## What the layer must do

A backend data source serves string values for string keys. Its `get(key)` is
slow (it models the network round-trip to the authoritative store), so you front
it with Redis. Your layer must implement three behaviours, all of which the
verifier exercises under real threading:

1. **Cache-aside with TTL.** `cached_get` checks Redis first. On a miss it
   fetches the value from the backend **exactly once** and stores it under the
   requested key with the TTL argument passed by the caller (`SET ... EX
   ttl_seconds`). The value must be served back to the caller as a `str`
   (`decode_responses=True`).
2. **Single-flight stampede protection.** When N callers miss the same key
   concurrently, exactly **one** of them performs the backend `get`; the other
   N-1 wait and reuse the freshly cached result. There must never be more than
   one in-flight backend fetch for the same key, and no caller may be left
   hanging or return a stale value after the key expired.
3. **Atomic compound read-modify-write.** The "spend" operation reads the
   current numeric balance at a key, and only if the balance is at least the
   requested amount subtracts the amount and reports success (else it reports
   failure). This check-then-write must be a **single atomic server-side Lua
   script** (one `EVAL`/`EVALSHA`), not a Python-side
   read-check-write sequence. Under concurrent spends there must be **no lost
   update**: the balance may never go negative, and the sum of amounts that
   were acknowledged must equal exactly what was removed from the balance.

## Deliverables (create exactly these two files)

### 1. `/app/start_redis.sh`

A shell script that starts a daemonized, non-persistent redis-server bound to
`127.0.0.1` on the port given as its **first argument** and exits 0 once the
server answers `PONG` (bounded wait, poll with `redis-cli -p <port> ping`).
Idempotent: if redis already answers on that port, exit 0 immediately. The
verifier calls it as `bash /app/start_redis.sh <port>` before every workload,
with a different port per workload — it must not assume a fixed port, a fixed
data directory, or a running server.

Suggested shape:

```sh
#!/bin/bash
PORT="${1:?usage: start_redis.sh <port>}"
DIR="/tmp/redis-$PORT"
mkdir -p "$DIR"
if redis-cli -p "$PORT" ping >/dev/null 2>&1; then exit 0; fi
redis-server --bind 127.0.0.1 --port "$PORT" --daemonize yes \
  --save "" --appendonly no --dir "$DIR" \
  --pidfile "$DIR/redis.pid" --logfile "$DIR/redis.log"
for i in $(seq 1 50); do
  redis-cli -p "$PORT" ping 2>/dev/null | grep -q PONG && exit 0
  sleep 0.2
done
exit 1
```

### 2. `/app/cache_layer.py`

A Python module exposing exactly this contract:

```python
def open_cache(host="127.0.0.1", port=6379):
    """Connect to the redis server and return a cache handle object.
    The handle must expose an attribute `client` that is the redis.Redis
    connection it uses."""

def cached_get(handle, key, backend, ttl_seconds):
    """Cache-aside read with single-flight stampede protection.
    `backend` is an object whose method backend.get(key) returns the
    authoritative value (it is slow and must be called at most once per
    miss window for a given key). Store the fetched value with EX ttl_seconds
    and return it as a str. Return the cached str on a hit."""

def spend(handle, key, amount):
    """Atomically debit `amount` from the integer balance at `key`
    (missing key counts as 0) iff the balance is at least `amount`.
    Return True on success, False on denial. Must be one server-side
    Lua script; concurrent spends must never overdraw or lose an update."""
```

The verifier imports `/app/cache_layer.py`, opens one handle per workload, and
calls these three functions from many threads. The key names, key values,
TTLs, ports and concurrency parameters all come from the workload fixtures at
verification time — nothing may be hard-coded.

## What is on disk

- `/app/workloads/visible_case.json` — the visible workload descriptor. Do
  **not modify** anything under `/app/workloads/`; the verifier reads it as the
  visible fixture and mounts fresh hidden workloads with the same schema.
- `redis-server`, `redis-cli`, Python 3.12.3, `redis` 7.0.1. Nothing else.

## Workload schema

Every workload (visible and hidden) is a JSON object:

| key | meaning |
|---|---|
| `port` | redis port to use for this workload (start your own server on it) |
| `ttl_seconds` | the TTL passed to `cached_get` |
| `backend_latency_s` | how long the backend sleeps per `get` (models RTT) |
| `values` | `{key: value}` the backend can serve; redis starts empty for these keys |
| `readers_per_key` | how many concurrent readers the verifier launches per key |
| `rounds` | how many miss windows the verifier runs (backend values change every round, so a stale cache is caught) |
| `spend_key` | balance key for the spend test (not among the read keys) |
| `spend_start` | the balance the verifier seeds before the spend test |
| `spend_workers`, `ops_per_worker`, `amount_min`, `amount_max` | spend concurrency: `spend_workers` threads each perform `ops_per_worker` spends of random integer amounts in `[amount_min, amount_max]` |

## How the verifier scores you

For every workload (the visible one plus three hidden ones with different
ports, keys, TTLs and concurrency) it:

1. runs `bash /app/start_redis.sh <port>` and waits for `PONG`, then flushes
   the database and opens your handle for that port;
2. drives `rounds` concurrent-miss windows: each round, `readers_per_key`
   threads per key hit `cached_get` simultaneously against an empty/expired
   cache, while the backend values are changed to a fresh generation; it
   asserts every reader got the **current** generation's value and that the
   backend was called **exactly once per key per round**;
3. between rounds it waits for the keys to expire (redis second-granularity
   TTL), asserting they really do;
4. after the last round it asserts every key's remaining TTL is within
   `[ttl_seconds-2, ttl_seconds+1]` seconds — a cache that ignores the TTL or
   doubles it fails;
5. seeds `spend_start` on the balance key and runs the concurrent spend
   workload, then asserts the balance never went negative and that
   `spend_start - (sum of acknowledged amounts) == final balance` — a
   check-then-write race shows up as overdraft or a lost update;
6. fails any workload if a reader or spend thread hangs (broken single-flight
   deadlock) or raises.

The container has `cpus = 1`, so keep everything single-process and single
thread pool; the concurrency in this task is thread-level I/O concurrency
against redis, which is what "concurrent load" means here.

Write `/app/cache_layer.py` and `/app/start_redis.sh`, make them robust for
arbitrary workloads of the schema above, and verify them locally by starting a
redis server on a port of your choice and running threaded tests against it.