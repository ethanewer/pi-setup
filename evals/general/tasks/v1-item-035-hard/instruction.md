# Item-035 (hard) — a concurrent, stateful gRPC KV server with atomic batch ops

Build a **concurrent, in-memory gRPC key/value server** that demonstrates the
full RPC development loop under pressure. Compared to the medium variant, the
hard contract adds an **atomic multi-key batch**, an **aggregate**, and a
**lifecycle reset**, and stresses the server with far more concurrency. You are
graded against a real gRPC client exercising all of these paths.

Work the right way round:

1. **Define the wire contract first** — write the Protocol Buffers `.proto`
   that fixes the RPC surface, then generate the Python stubs from it (never
   hand-write messages).
2. **Bring up a live server** with that generated code and serve it over gRPC.
3. **Prove it with a real client** — repeated, concurrent, batch, and lifecycle
   requests, checking both positive and negative paths.

## Wire contract (exact — write it byte-for-byte compatible)

Create the schema at **`/app/proto/service.proto`** with *exactly* this content
(package `kvstore`):

```proto
syntax = "proto3";

package kvstore;

message PingRequest  { string nonce = 1; }
message PingResponse { string nonce = 1; }

message SetRequest   { string key = 1; int64 value = 2; }
message SetResponse  { bool ok = 1; }

message GetRequest   { string key = 1; }
message GetResponse  { bool found = 1; int64 value = 2; }

message IncRequest   { string key = 1; int64 delta = 2; }
message IncResponse  { int64 value = 1; }

message MultiGetRequest  { repeated string keys = 1; }
message MultiGetResponse { map<string, int64> values = 1; }

message BatchIncRequest   { repeated string keys = 1; int64 delta = 2; }
message BatchIncResponse  { map<string, int64> values = 1; }

message SumRequest  { repeated string keys = 1; }
message SumResponse { int64 total = 1; }

message ResetRequest  {}
message ResetResponse { int32 cleared = 1; }

service KVStore {
  rpc Ping     (PingRequest)     returns (PingResponse);
  rpc Set      (SetRequest)      returns (SetResponse);
  rpc Get      (GetRequest)      returns (GetResponse);
  rpc Inc      (IncRequest)      returns (IncResponse);
  rpc MultiGet (MultiGetRequest) returns (MultiGetResponse);
  rpc BatchInc (BatchIncRequest) returns (BatchIncResponse);
  rpc Sum      (SumRequest)      returns (SumResponse);
  rpc Reset    (ResetRequest)    returns (ResetResponse);
}
```

The service runs at **`127.0.0.1:50051`** (plaintext, insecure channel).

## Server: `/app/server.py`

Write `/app/server.py` that:
- Uses `grpc_tools.protoc` (preinstalled) to compile `/app/proto/service.proto`
  into generated `*_pb2.py` / `*_pb2_grpc.py` under `/app/generated/` at
  startup, then imports them.
- Implements **every** RPC:
  - `Ping` — return the same `nonce` string.
  - `Set` — store `int64 value` under `key`; return `ok=true`.
  - `Get` — `found=false` when absent, else `found=true` with the value.
  - `Inc` — atomically add `delta` to the existing value (missing = 0), return
    the **new** value.
  - `MultiGet` — map of existing keys → current values (missing → 0).
  - `BatchInc` — for **several** keys at once, add `delta` to each and return
    the new value of every key as a map. This must be **atomic with respect to
    single-key `Inc`s**: if two `Inc`s and a `BatchInc` touch overlapping keys,
    no update may be lost.
  - `Sum` — return the sum of the current values of every listed key (missing
    treated as 0).
  - `Reset` — wipe all stored keys and return `cleared` = number of keys that
    were present before the reset.
- Keeps a **single in-memory state that persists across requests** (repeat
  `Set`/`Get`/`Inc`/`BatchInc` calls see previous effects).
- Serves with a **threaded (concurrent) gRPC server** and is
  **concurrency-correct**: a lock (or equivalent) must make every mutation on a
  key atomic so concurrent `Inc`s and `BatchInc`s never lose an update.

Start it and leave it running (or make it runnable so the verifier can start it
on demand).

## Deliverables (graded)

- `/app/proto/service.proto` — the wire contract (exact content above).
- `/app/server.py` — runnable gRPC server implementing the contract on
  `127.0.0.1:50051`.
- Server up and serving on `50051` when you finish.

## What the verifier checks (so you can self-test)

The harness compiles your `.proto` into its **own** client stubs, connects to
your live server, and asserts:

1. **Lifecycle / Ping**: `Ping` echoes its `nonce`.
2. **Set + Get**: `Set("alpha",10)` then `Get("alpha")` → `found=true`,
   `value=10`. Fresh `Get("nope")` → `found=false`.
3. **Repeat / state persistence**: `Set("alpha",10)`; `Inc("alpha",5)` → 15;
   `Inc("alpha",7)` → 22 — the *same* server returns the running total.
4. **MultiGet**: after the above, `MultiGet(["alpha","beta"])` →
   `alpha=22`, `beta=0`.
5. **Concurrency (single key)**: **80 threads** each call `Inc("ctr",1)`;
   afterwards `Get("ctr").value` must be exactly `80`. Any lost update drops
   the score.
6. **Concurrent single-key + batch mixing**: clear the store, then start **20
   threads** that each do `Inc("k",1)` **and** **20 threads** that each do
   `BatchInc(["k"],1)` on the same key concurrently. Afterwards
   `Get("k").value` must be exactly **40** (atomicity — no lost update).
7. **Batch aggregate + deltas**: `BatchInc(["a","b"], 3)` → `{a:3,b:3}`; then
   `Sum(["a","b","z"])` → `6` (z missing → 0).
8. **Reset lifecycle**: `Reset()` returns a non-negative count, and after
   `Reset()`, `Get` of a formerly-set key returns `found=false`.

The exact key names incorporate a random per-run namespace, so do not assume
specific values; just implement the semantics. All packages are preinstalled
(`grpcio`, `grpcio-tools`, `protobuf`).