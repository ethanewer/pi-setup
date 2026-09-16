# Windlass DispatchService: finish the schema v2 migration

The Windlass logistics gateway's order-dispatch service is a **Go** gRPC
server. The full repository is checked out at `/app/windlass-dispatch` (a
git repository with its history). The service contract lives in
`proto/dispatch.proto`; the repo also carries checked-in generated bindings
(Go under `dispatch.v2/`, Python under `client/`), a Python CLI
(`client/client.py`), a Makefile, and a contract test suite (`tests/`).

The schema recently migrated from v1 to v2 (see `docs/SCHEMA_MIGRATION.md`
and the archived `proto/dispatch_v1.proto`): **field 2 was renamed, a
`packaging` oneof (Box | Envelope) was added, and `special_instructions` was
deprecated** — legacy clients still send that field and must keep getting it
back. Because wire tag numbers were kept, v1-shaped payloads (no packaging
oneof) are valid v2 payloads and must be answered correctly.

At HEAD the repository is **not in a working state**: it does not build as
checked out. Your job is to make the deliverable complete and correct:

1. **Consistency.** The schema in `proto/dispatch.proto` is authoritative.
   Every artifact that must agree with it — including any checked-in
   generated code — must be brought into agreement, and the project must
   build: the Go server must compile. Do **not** edit the schema itself.
2. **Correctness.** The running server must implement the documented receipt
   semantics (see `README.md`, "Receipt semantics" and "Deprecation policy"):
   `SubmitOrder` must return receipts whose echoed fields are **exactly**
   what was sent, whose `packaging_kind`/`route_code` follow the documented
   rules for both old-shaped (no packaging) and new-shaped (box / envelope)
   requests, and whose **deprecated field is preserved verbatim** — a
   receipt that silently drops it is a regression.
3. **Deliverable.** Provide **`/app/windlass-dispatch/serve.sh`** — a
   production serve script with this exact contract:

   - invoked as `serve.sh [PORT]` (one optional positional argument, default
     50333), exit status 0 on success and non-zero on any failure;
   - must ensure the repository is consistent with the current schema and
     the Go server is built, then start `windlass-server` listening on
     `0.0.0.0:PORT`;
   - must wait until the server accepts connections before exiting 0;
   - must write the server's PID to `/app/windlass-dispatch/.server.pid`.

## Environment

- `golang-go` 1.22 with the modget runtime; the project's `go.mod`/`go.sum`
  are already shipped and the dependency cache is warm — `go build` works
  without network from `/app/windlass-dispatch`.
- `protoc` 3.21 with the Go gRPC plugins `protoc-gen-go` /
  `protoc-gen-go-grpc` preinstalled on PATH, and `grpcio` / `grpcio-tools`
  (the Python `grpc_tools.protoc`) preinstalled, plus `pytest`.
- The container has **no network**. Do not add or change dependencies.
- The Python client imports its bindings from `client/` next to it; keep
  that layout (the grader's clients import the bindings from your
  repository's `client/` directory).

## How you will be graded

The grader runs your `serve.sh` on port 50444 and then drives the running
service with **hidden Python clients** that send old-shape and new-shape
requests (legacy / box / envelope: differing addresses, weights, packaging
dimensions, and instruction strings including unicode and whitespace-edge
cases). Each client recomputes the documented `route_code`/`packaging_kind`
rules and asserts them, plus exact echo of `tracking_id`,
`delivery_address`, and `special_instructions`. All clients must pass.