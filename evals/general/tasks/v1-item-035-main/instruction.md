# Item-035 (medium) — define the wire contract, then run a live gRPC KV server

You are building a **concurrent, in-memory gRPC key/value counter server**. The
point is to demonstrate the full RPC development loop the right way round:

1. **Define the wire contract first** — write the Protocol Buffers `.proto` that
   fixes the RPC surface, then generate the Python stubs from it (never hand-write
   messages).
2. **Bring up a live server** with that generated code and serve it over gRPC.
3. **Prove it with a real client** that sends repeated and **concurrent** requests,
   and check both positive and negative paths.

## Wire contract (exact — write it byte-for-byte compatible)

Create the protobuf schema file at **`/app/proto/service.proto`** with *exactly*
this content (package `kvstore`):

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

service KVStore {
  rpc Ping    (PingRequest)    returns (PingResponse);
  rpc Set     (SetRequest)     returns (SetResponse);
  rpc Get     (GetRequest)     returns (GetResponse);
  rpc Inc     (IncRequest)     returns (IncResponse);
  rpc MultiGet(MultiGetRequest) returns (MultiGetResponse);
}
```

The service runs at **`127.0.0.1:50051`** (plaintext, insecure channel).

## Server: `/app/server.py`

Write `/app/server.py` that:
- Uses `grpc_tools.protoc` (already installed) to compile
  `/app/proto/service.proto` into generated `*_pb2.py` / `*_pb2_grpc.py` under
  `/app/generated/` at startup (regenerate every run), then imports them.
- Implements **every** RPC per the contract:
  - `Ping` — return the same `nonce` string.
  - `Set` — store the int64 `value` keyed by `key`; return `ok=true`.
  - `Get` — return `found=false` when the key is absent, else `found=true` with
    the current `value`.
  - `Inc` — atomically add `delta` to the existing value (missing = 0) and return
    the **new** value.
  - `MultiGet` — return a map of existing keys -> values (missing keys are left
    out / treated as 0; your choice, be consistent).
- Keeps a single in-memory state that **persists across requests** (repeat `Set`/
  `Get`/`Inc` calls see previous effects). Do **not** drop state per request.
- Serves with a **threaded (concurrent) gRPC server** (e.g. a
  `ThreadPoolExecutor` with many workers) and is **concurrency-correct**: uses a
  lock so concurrent `Inc`s on the same key never lose an update.

Start it and leave it running (or make it runnable so the verifier can start it).

## Deliverables (graded)

- `/app/proto/service.proto` — the wire contract (exact content above).
- `/app/server.py` — runnable gRPC server implementing that contract on
  `127.0.0.1:50051`.
- Server up and serving on `50051` when you finish.

## Behavior the verifier checks (so you can self-test)

The harness will compile your `.proto` into its **own** client stubs, connect to
your live server, and assert:

1. **Lifecycle / Ping**: `Ping` echoes its `nonce`.
2. **Set + Get**: after `Set("alpha", 10)`, `Get("alpha")` → `found=true`,
   `value=10`. A fresh `Get("nope")` → `found=false`.
3. **Repeat / state persistence**: `Set("alpha", 10)`; `Inc("alpha", 5)` → 15;
   `Inc("alpha", 7)` → 22 — the *same* server must return the running total
   across separate calls.
4. **MultiGet**: after the above, `MultiGet(["alpha","beta"])` returns
   `alpha=23` and `beta` absent/0.
5. **Concurrency**: 20 threads each call `Inc("ctr", 1)`; afterwards
   `Get("ctr").value` must be exactly `20` (an atomic counter — any lost update
   drops the score).

Use `grpc` and the generated stubs exactly; do not skip the proto-compile step.
All packages are preinstalled (`grpcio`, `grpcio-tools`, `protobuf`).