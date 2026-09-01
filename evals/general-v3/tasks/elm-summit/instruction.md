# AtlasRidge cluster control-plane

You are the operator at **AtlasRidge**, a small on-prem object-keying fleet. You
must bring up a lean, real control-plane from the provided Python + gRPC +
MLflow stack. Everything is local and single-host. You will write ONE Python
program that (a) serves a live gRPC gateway (a key/value store plus a cluster
status endpoint) and (b) launches a local **mlflow tracking server** in the
background. Both must stay up — the verifier probes them while it runs.

## Deliverable

Create and launch **`/app/serve.py`** (a single, self-contained Python 3
program). It is the only artifact you must produce. It must:

1. Run a gRPC gateway server implementing the `AtlasGateway` service described
   below, bound to a specific port, and keep serving until it is killed.
2. When run in **launch** mode (no port argument, see CLI contract), also start
   a local **mlflow tracking server** in the background on `127.0.0.1:8080`
   and keep it reachable while the process lives.

## Provided fixtures (do NOT modify or overwrite)

- `/app/atlas.proto` — the gRPC contract (gives you the exact RPC names,
  fields and types below). It is already registered to generate stubs.
- `/app/atlas_pb2.py` and `/app/atlas_pb2_grpc.py` — the compiled stubs,
  already generated in `/app`. Your `serve.py` **must import** these
  (`import atlas_pb2` / `import atlas_pb2_grpc`) rather than recompile or
  redefine the messages. Do not delete or overwrite them.
- `/app/config.json` — a JSON object describing the cluster. The verifier will
  also drive your program with **other** config files on OTHER ports / other
  store paths, so read the config from disk every run and never hardcode the
  visible cluster's numbers.

The Python environment has `grpcio`, `grpcio-tools`, `protobuf`, and `mlflow`
installed. Use only these plus the standard library.

## CLI contract

```
python3 /app/serve.py            # LAUNCH mode
python3 /app/serve.py launch     # same as no argument
python3 /app/serve.py <PORT>     # gRPC-only mode: serve on 0.0.0.0:<PORT>
```

- **Launch mode (no port):** read the config (see "cluster config" below),
  start the mlflow tracking server in the background on `127.0.0.1:8080`, then
  bind the gRPC gateway on `0.0.0.0:<config.port>` and keep serving. Use the
  real `mlflow` CLI / its Python `mlflow.server` entry; the tracking server
  must be reachable at `http://127.0.0.1:8080/health` (an HTTP 200) while the
  program runs. If mlflow needs a database backing store (newer releases reject
  the legacy filesystem store), use a `sqlite:///...` backend under the config
  mlflow dir, or set `MLFLOW_ALLOW_FILE_STORE=true`; either is fine as long as
  it starts and stays up.
- **gRPC-only (`<PORT>`):** bind the gRPC gateway on `0.0.0.0:<PORT>` and serve.
  No mlflow is started in this mode. The verifier uses this mode to exercise
  the gateway on fresh ports/configs. It must be a foreground process that
  stays alive (a blocking serve loop); do not exit after the first RPC.

Both modes must bind and begin serving immediately and remain serving until
terminated.

## How the verifier drives your program

Besides the live launch mode it probes on the visible cluster, the verifier
re-runs `/app/serve.py <PORT>` in gRPC-only mode against up to three hidden
clusters, each with its own config file, port, store path and key set. It
points your program at a hidden config with the environment variable

```
ATLAS_CONFIG=/path/to/that/config.json
```

Your program must be written so hidden runs behave exactly like launch mode:

- At startup, load the config from the path in `ATLAS_CONFIG` if that variable
  is set; otherwise load `/app/config.json`. Always read the file from disk on
  every run — never bake the visible cluster's values (cluster name, nodes,
  capacity, port, store path) into the program.
- In gRPC-only mode the gateway port is the command-line argument; every other
  setting (`cluster`, `nodes`, `capacity_bytes`, `store_path`, optional
  `mlflow_store`) must come from the loaded config.
- Each hidden config uses a fresh `store_path` and a fresh port. One hidden
  case terminates your process and restarts it on a NEW port with the SAME
  config file: keys written before the restart must still come back on `Get`,
  because the store lives at the config's `store_path` on disk (not in memory,
  not bound to the old port).
- Hidden config files may contain extra keys your program does not use (for
  example `restart`, `port2`); ignore them.
- Hidden runs are gRPC-only and do not start mlflow; your program must not
  require mlflow in that mode (no mlflow daemon must be launched when a port
  argument is given).

## Config file ("/app/config.json", JSON)

```json
{
  "cluster": "atlas-ridge-07",
  "nodes": ["ridge-a-01", "ridge-b-02", "ridge-c-03"],
  "capacity_bytes": 4294967294,
  "port": 5000,
  "store_path": "/tmp/atlas_ridge/kv_state.json",
  "mlflow_store": "/tmp/atlas_ridge/mlflow"
}
```

- `cluster`: string cluster name. Expose it verbatim in `Status`.
- `nodes`: list of string data-plane node names. Expose them verbatim.
- `capacity_bytes`: integer, the cluster's configured storage capacity. Expose
  it as an int64 in `Status`, unmodified.
- `port`: UDP/TCP port the launch mode should bind the gateway to.
- `store_path`: where the key/value store lives on disk. Create any parent
  directory. The store must SURVIVE process restarts (verifier restarts the
  gateway on this same store and expects the keys back).
- Optional `mlflow_store`: directory for the mlflow backend / artifact root.

## The `AtlasGateway` service (from /app/atlas.proto)

Your gateway must implement every RPC so a client strikes direct round-trips:

- `Put(PutReq{key,value}) → PutReply{ok}`. Store the string `value` under
  string `key` in `store_path`'s store. `ok=true` on success. Store must be
  durable (write it to disk) and atomic with respect to concurrent puts.
- `Get(GetReq{key}) → ValueMsg{value}`. Return the exact stored string for
  `key`. If `key` was never written, abort the call with gRPC status
  `NOT_FOUND` (do not fabricate a value).
- `Status(StatusReq{probe_id}) → StatusInfo`:
  - `healthy` = `true` when the store opened and the gateway's service is
    online.
  - `cluster` = cluster name from config.
  - `nodes` = node list from config (order not important, membership is).
  - `capacity_bytes` = config capacity, unmodified.
  - `objects` = the number of distinct keys currently in the store.
  - `detail` = free-form; include the probe_id plus the literal word `online`
    (e.g. build it from the request's probe_id) so the endpoint unambiguously
    reports the cluster online.

The gateway must survive: a client may do many puts (hundreds), long values,
distinct keys, and — for one hidden case — restart the process on the same
store and read back earlier writes.

## What you must do

1. Write `/app/serve.py` to implement all of the above.
2. Run it in **launch** mode in the background so that, when the verifier runs,
   the gRPC gateway is live on the configured port AND the mlflow tracking
   server is reachable at `http://127.0.0.1:8080/health`. The verifier will not
   start mlflow for you — it only checks that your instance is up.
3. Do NOT read or depend on anything under `/tests`. Do NOT overwrite
   `/app/atlas_pb2.py` and `/app/atlas_pb2_grpc.py`. Do NOT replace or delete
   `/app/atlas.proto` or `/app/config.json`.

## How you'll be scored

The verifier (a) confirms a live mlflow server on `127.0.0.1:8080`, (b) round-trips
`Put`/`Get` against your launch-mode gateway on the visible cluster, checking a
`Status` that reports `healthy=true`, the exact cluster name/nodes/capacity,
and an `objects` count, and (c) re-runs your `/app/serve.py <port>` against up
to three hidden clusters/configs — including a restart/persistence case — and
checks the same behavior there. Miss any of it (gateway not listening, wrong
port, mlflow dead, dropped writes) and the reward is `0`.