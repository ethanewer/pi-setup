#!/usr/bin/env bash
# Build the Windlass DispatchService repository (with git history) under
# /app/windlass-dispatch. Runs once at image build time, then deletes itself.
# HEAD deliberately ships half-migrated: the v2 schema is authoritative while
# the checked-in bindings are the un-refreshed v1 generation and the receipt
# builder regressed. That is the work surface the agent gets.
set -euo pipefail
export PATH="/usr/local/bin:$PATH"
REPO=/app/windlass-dispatch
git config --system --add safe.directory '*' || true
git config --system user.email 'build@localhost' || true
git config --system user.name 'build' || true
rm -rf "$REPO" && mkdir -p "$REPO"/proto "$REPO"/client "$REPO"/docs "$REPO"/tests
cd "$REPO"
git init -q
echo '--- C1: initial v1 service ---'
cat > 'go.mod' <<'WD_EOF_GO_MOD'
module windlass.dispatch.v2

go 1.25.0

require (
	google.golang.org/grpc v1.83.2
	google.golang.org/protobuf v1.36.11
)

require (
	golang.org/x/net v0.58.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
)
WD_EOF_GO_MOD
cat > 'go.sum' <<'WD_EOF_GO_SUM'
github.com/cespare/xxhash/v2 v2.3.0 h1:UL815xU9SqsFlibzuggzjXhog7bL6oX9BbNZnL2UFvs=
github.com/cespare/xxhash/v2 v2.3.0/go.mod h1:VGX0DQ3Q6kWi7AoAeZDth3/j3BFtOZR5XLFGgcrjCOs=
github.com/go-logr/logr v1.4.3 h1:CjnDlHq8ikf6E492q6eKboGOC0T8CDaOvkHCIg8idEI=
github.com/go-logr/logr v1.4.3/go.mod h1:9T104GzyrTigFIr8wt5mBrctHMim0Nb2HLGrmQ40KvY=
github.com/go-logr/stdr v1.2.2 h1:hSWxHoqTgW2S2qGc0LTAI563KZ5YKYRhT3MFKZMbjag=
github.com/go-logr/stdr v1.2.2/go.mod h1:mMo/vtBO5dYbehREoey6XUKy/eSumjCCveDpRre4VKE=
github.com/golang/protobuf v1.5.4 h1:i7eJL8qZTpSEXOPTxNKhASYpMn+8e5Q6AdndVa1dWek=
github.com/golang/protobuf v1.5.4/go.mod h1:lnTiLA8Wa4RWRcIUkrtSVa5nRhsEGBg48fD6rSs7xps=
github.com/google/go-cmp v0.7.0 h1:wk8382ETsv4JYUZwIsn6YpYiWiBsYLSJiTsyBybVuN8=
github.com/google/go-cmp v0.7.0/go.mod h1:pXiqmnSA92OHEEa9HXL2W4E7lf9JzCmGVUdgjX3N/iU=
github.com/google/uuid v1.6.0 h1:NIvaJDMOsjHA8n1jAhLSgzrAzy1Hgr+hNrb57e+94F0=
github.com/google/uuid v1.6.0/go.mod h1:TIyPZe4MgqvfeYDBFedMoGGpEw/LqOeaOT+nhxU+yHo=
go.opentelemetry.io/auto/sdk v1.2.1 h1:jXsnJ4Lmnqd11kwkBV2LgLoFMZKizbCi5fNZ/ipaZ64=
go.opentelemetry.io/auto/sdk v1.2.1/go.mod h1:KRTj+aOaElaLi+wW1kO/DZRXwkF4C5xPbEe3ZiIhN7Y=
go.opentelemetry.io/otel v1.44.0 h1:JjwHmHpA4iZ3wBxluu2fbbE7j4kqlE8jXyAyPXH7HqU=
go.opentelemetry.io/otel v1.44.0/go.mod h1:BMgjTHL9WPRlRjL2oZCBTL4whCGtXch2H4BhOPIAyYc=
go.opentelemetry.io/otel/metric v1.44.0 h1:1w0gILTcHdr3YI+ixLyjemwrVnsMURbTZFrSYCdDdmc=
go.opentelemetry.io/otel/metric v1.44.0/go.mod h1:8O7hanEPBNgEMmybD3s2VBKcgWOCsA6tzHBPODAiquo=
go.opentelemetry.io/otel/sdk v1.44.0 h1:nHYwb9lK+fJPU/dnT6s7W7Z8itMWyqrnVfbheVYrZ58=
go.opentelemetry.io/otel/sdk v1.44.0/go.mod h1:Osuydd3Se74nqjAKxid74N5eC+jfEqfTegHRnq58oK0=
go.opentelemetry.io/otel/sdk/metric v1.44.0 h1:3LlKgI+VjbVsjNRFZJZAJ30WjXC5VkNRks6si09iEfI=
go.opentelemetry.io/otel/sdk/metric v1.44.0/go.mod h1:5B5pMARnXxKhltooO4xUuCBorl65a4EpnTalObqOigA=
go.opentelemetry.io/otel/trace v1.44.0 h1:jxF5CsGYCe74MCRx2X4g7WsY/VBKRqqpNvXlX/6gtIk=
go.opentelemetry.io/otel/trace v1.44.0/go.mod h1:oLl1jrMQAVo6v3GAggN+1VH9VIz9iUSvW53sW1Q8PIE=
golang.org/x/net v0.58.0 h1:ynWG7rqYi4ccpTEuPZ2QGWHktVEM9DMCj9yzDE0Q7To=
golang.org/x/net v0.58.0/go.mod h1:YwCddHnFlT7eLQqVprV19OnhLGtc5xOKgE0RyqgfWAU=
golang.org/x/sys v0.47.0 h1:o7XGOvZQCADBQQ4Y7VNq2dRWQR7JmOUW8Kxx4ZsNgWs=
golang.org/x/sys v0.47.0/go.mod h1:4GL1E5IUh+htKOUEOaiffhrAeqysfVGipDYzABqnCmw=
golang.org/x/text v0.41.0 h1:vz/seA0lnX87Othu2f/0L24RcgrXD9/YFTSuGjj3rH8=
golang.org/x/text v0.41.0/go.mod h1:jvf1O8ajNzZqhSrQBPbutR/EB83Cc0CFrezNQIwbb5M=
gonum.org/v1/gonum v0.17.0 h1:VbpOemQlsSMrYmn7T2OUvQ4dqxQXU+ouZFQsZOx50z4=
gonum.org/v1/gonum v0.17.0/go.mod h1:El3tOrEuMpv2UdMrbNlKEh9vd86bmQ6vqIcDwxEOc1E=
google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa h1:mZHHdPZl0dbGHCflZgAq/Q468DWVFcU2whhB2KAo8fk=
google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa/go.mod h1:4Hqkh8ycfw05ld/3BWL7rJOSfebL2Q+DVDeRgYgxUU8=
google.golang.org/grpc v1.83.2 h1:EManeRomTObA0BU7I8vXgg/78uE5MJ9M8B39EX2WscU=
google.golang.org/grpc v1.83.2/go.mod h1:YPI1hK3kDked6iHvgX3tR0y+nX/qpMFKhPgFsokw1S8=
google.golang.org/protobuf v1.36.11 h1:fV6ZwhNocDyBLK0dj+fg8ektcVegBBuEolpbTQyBNVE=
google.golang.org/protobuf v1.36.11/go.mod h1:HTf+CrKn2C3g5S8VImy6tdcUvCska2kB7j23XfzDpco=
WD_EOF_GO_SUM
cat > 'proto/dispatch.proto' <<'WD_EOF_V1_PROTO'
syntax = "proto3";

// Windlass DispatchService contract, schema v1 (the original wire format).
//
// v1 stayed live until 2026-02 and legacy clients still speak this shape over
// the wire: field tags are unchanged in v2, so v1 payloads keep working.
// When the schema evolves further, never reuse tags 1..6.
//
// See proto/dispatch.proto for the current v2 schema and
// docs/SCHEMA_MIGRATION.md for the v1 -> v2 change log.

package windlass.dispatch.v1;

option go_package = "dispatch.v2";

message Order {
  string tracking_id = 1;
  string dest_address = 2;
  string special_instructions = 3;
  int32 weight_grams = 4;
  message DestinationBox {
    int32 width_mm = 1;
    int32 height_mm = 2;
    int32 depth_mm = 3;
  }
  DestinationBox box_padding = 5;
}

message DispatchReceipt {
  string tracking_id = 1;
  string dest_address = 2;
  string special_instructions = 3;
  string route_code = 4;
  string packaging_kind = 5;
}

service DispatchService {
  rpc SubmitOrder(Order) returns (DispatchReceipt);
}
WD_EOF_V1_PROTO
cat > 'Makefile' <<'WD_EOF_MAKEFILE'
# Windlass DispatchService. The .proto is the single source of truth; the
# checked-in bindings under dispatch.v2/ and client/ are generated artifacts.
# Refresh them with `make gen` whenever proto/dispatch.proto changes.

GEN_GO := protoc -I proto --go_out=. --go-grpc_out=. proto/dispatch.proto
GEN_PY := python3 -m grpc_tools.protoc -I proto --python_out=client --grpc_python_out=client proto/dispatch.proto

.PHONY: gen build serve test

gen:
	$(GEN_GO)
	$(GEN_PY)

build: gen
	go build -o windlass-server

serve: build
	./windlass-server --port=50333

test:
	python3 -m pytest tests -q
WD_EOF_MAKEFILE
# generate the v1 checked-in bindings (proto is still v1 at this point)
protoc -I proto --go_out=. --go-grpc_out=. proto/dispatch.proto
python3 -m grpc_tools.protoc -I proto --python_out=client --grpc_python_out=client proto/dispatch.proto

cat > 'main.go' <<'WD_EOF_V1_MAIN'
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"

	"google.golang.org/grpc"
	pb "windlass.dispatch.v2/dispatch.v2"
)

var (
	port = flag.Int("port", 50333, "port to listen on")
)

type dispatchServer struct {
	pb.UnimplementedDispatchServiceServer
}

func (s *dispatchServer) SubmitOrder(_ context.Context, in *pb.Order) (*pb.DispatchReceipt, error) {
	kind := "loose"
	if in.GetBoxPadding() != nil {
		kind = "boxed"
	}
	return &pb.DispatchReceipt{
		TrackingId:      in.GetTrackingId(),
		DestAddress:     in.GetDestAddress(),
		SpecialInstructions: in.GetSpecialInstructions(),
		RouteCode:       fmt.Sprintf("ROUTE-LEGACY:%s:%s", kind, in.GetDestAddress()),
		PackagingKind:   kind,
	}, nil
}

func main() {
	flag.Parse()
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("listen failed: %v", err)
	}
	svc := grpc.NewServer()
	pb.RegisterDispatchServiceServer(svc, &dispatchServer{})
	log.Printf("dispatch server listening on %v", lis.Addr())
	if err := svc.Serve(lis); err != nil {
		log.Fatalf("serve failed: %v", err)
	}
}
WD_EOF_V1_MAIN
cat > 'client/client.py' <<'WD_EOF_V1_CLIENT_PY'
#!/usr/bin/env python3
"""Windlass DispatchService CLI client (schema v1, legacy)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import grpc  # noqa: E402

import dispatch_pb2 as pb  # noqa: E402
import dispatch_pb2_grpc as service  # noqa: E402


def main():
    chan = grpc.insecure_channel("127.0.0.1:%d" % int(os.environ.get("DISPATCH_PORT", "50333")))
    stub = service.DispatchServiceStub(chan)
    order = pb.Order()
    order.tracking_id = "ORD-000"
    order.dest_address = "1 Old Pier"
    order.special_instructions = "ring twice"
    order.weight_grams = 9000
    receipt = stub.SubmitOrder(order, timeout=20)
    print("tracking_id:      %s" % receipt.tracking_id)
    print("dest_address:     %s" % receipt.dest_address)
    print("special_instr:    %r" % receipt.special_instructions)
    print("route_code:       %s" % receipt.route_code)


if __name__ == "__main__":
    main()
WD_EOF_V1_CLIENT_PY
git add -A && git commit -q -m 'Initial DispatchService (v1 wire shape)'
echo '--- C2: layout docs ---'
cat > 'docs/SCHEMA_MIGRATION.md' <<'WD_EOF_MIGRATION_DOC'
# Schema migration v1 -> v2 (2026-03)

Applied in commit "Migrate DispatchService to the v2 schema".

| Change | v1 | v2 |
|---|---|---|
| field 2 | `dest_address` | renamed to `delivery_address` (tag 2 unchanged) |
| field 5 | `box_padding` (fixed) | now `Box`, first arm of the new `packaging` oneof |
| field 6 | — | new `Envelope` arm of the oneof |
| field 3 | `special_instructions` | deprecated (still sent by legacy clients) |
| service | `SubmitOrder` | gained `Ping` |

Wire compatibility: because tag numbers were kept, v1 payloads (field 2
strings, no packaging oneof) are valid v2 payloads. The server must answer
both shapes correctly.

Checklist for future migrations:

1. Edit `proto/dispatch.proto`.
2. Run `make gen` and commit the refreshed bindings.
3. Make the server compile, then run `make test` against a live server.
4. Confirm legacy-shaped requests still return correct receipts.
WD_EOF_MIGRATION_DOC
cat > 'README.md' <<'WD_EOF_READMe'
# Windlass DispatchService

gRPC order-dispatch service for the Windlass logistics gateway. The Go
server (`main.go`) implements the contract in `proto/dispatch.proto`; the
Python client in `client/client.py` drives it.

## Layout

| Path | What it is |
|---|---|
| `proto/dispatch.proto` | **authoritative** schema (v2) |
| `proto/dispatch_v1.proto` | archived v1 schema (reference only) |
| `docs/SCHEMA_MIGRATION.md` | v1 -> v2 change log |
| `dispatch.v2/` | checked-in Go bindings (protoc `--go_out`, `--go-grpc_out`) |
| `client/` | Python bindings + `client.py` CLI |
| `main.go` | the Go service entrypoint |
| `tests/` | contract tests (need a running server) |

The bindings are generated with `protoc` and checked in; refresh them with
`make gen` whenever the schema changes. The Go toolchain (`golang-go`, modget
runtime), `protoc` 3.21 plus the `protoc-gen-go` / `protoc-gen-go-grpc`
plugins, and the `grpcio` / `grpcio-tools` python packages are preinstalled
in this image.

## Running everything

```console
$ make gen                     # regenerate bindings from the current proto
$ make build                   # gen + compile the Go server (go build -o windlass-server)
$ ./windlass-server --port=50333 &
$ python3 client/client.py --address "12 Dock Street" --weight 4000 --box 300x200x150
```

## Receipt semantics (service contract)

`SubmitOrder` returns a `DispatchReceipt` where:

- `tracking_id`, `delivery_address`, `special_instructions` echo the order.
- `packaging_kind` is one of `box`, `envelope`, `loose`.
- `route_code` is `ROUTE:<packaging>:<weight-class>:<address-slug>` where
  - `<packaging>` is `box<W>-<H>-<D>`, `env<T>`, or `loose`;
  - `<weight-class>` is `heavy` for `weight_grams >= 10000`, else `light`;
  - `<address-slug>` is the trimmed, lowercased address with each run of
    spaces replaced by `-`.

## Deprecation policy

Schema v2 deprecates `Order.special_instructions`, but legacy clients still
send it, and a receipt that silently drops it would break them. Preserving it
is part of the service contract: receipts must carry back **exactly** the
value the caller sent. Any redesign that loses the deprecated field is a
regression.
WD_EOF_READMe
git add -A && git commit -q -m 'Document layout, route rules and deprecation policy'
echo '--- C3: migrate to v2 schema ---'
cat > 'proto/dispatch_v1.proto' <<'WD_EOF_V1_ARCHIVE'
syntax = "proto3";

// Windlass DispatchService contract, schema v1 (the original wire format).
//
// v1 stayed live until 2026-02 and legacy clients still speak this shape over
// the wire: field tags are unchanged in v2, so v1 payloads keep working.
// When the schema evolves further, never reuse tags 1..6.
//
// See proto/dispatch.proto for the current v2 schema and
// docs/SCHEMA_MIGRATION.md for the v1 -> v2 change log.

package windlass.dispatch.v1;

option go_package = "dispatch.v2";

message Order {
  string tracking_id = 1;
  string dest_address = 2;
  string special_instructions = 3;
  int32 weight_grams = 4;
  message DestinationBox {
    int32 width_mm = 1;
    int32 height_mm = 2;
    int32 depth_mm = 3;
  }
  DestinationBox box_padding = 5;
}

message DispatchReceipt {
  string tracking_id = 1;
  string dest_address = 2;
  string special_instructions = 3;
  string route_code = 4;
  string packaging_kind = 5;
}

service DispatchService {
  rpc SubmitOrder(Order) returns (DispatchReceipt);
}
WD_EOF_V1_ARCHIVE
cat > 'proto/dispatch.proto' <<'WD_EOF_V2P'
syntax = "proto3";

// Windlass DispatchService contract, schema v2 (current).
//
// v2 changes from v1 (see docs/SCHEMA_MIGRATION.md and proto/dispatch_v1.proto):
//   - Order field 2 renamed: dest_address -> delivery_address (tag unchanged).
//   - Order field 5: the fixed `box_padding` became the Box arm of a new
//     `packaging` oneof; tag 6 (Envelope) is new.
//   - Order.special_instructions (tag 3) is DEPRECATED. Legacy clients still
//     send it and MUST receive it back verbatim: dropping it silently is a
//     regression against the deprecation policy in README.md.
//
// The Go bindings use go_package "dispatch.v2" and the python bindings are
// emitted next to the client under client/. Refresh the checked-in bindings
// with `make gen` whenever this file changes.

package windlass.dispatch.v2;

option go_package = "dispatch.v2";

message Order {
  string tracking_id = 1;
  string delivery_address = 2;
  string special_instructions = 3 [deprecated = true];
  int32 weight_grams = 4;
  oneof packaging {
    Box box = 5;
    Envelope envelope = 6;
  }
}

message Box { int32 width_mm = 1; int32 height_mm = 2; int32 depth_mm = 3; }
message Envelope { int32 thickness_mm = 1; }

message DispatchReceipt {
  string tracking_id = 1;
  string delivery_address = 2;
  string special_instructions = 3;
  string route_code = 4;
  string packaging_kind = 5;
}

service DispatchService {
  rpc SubmitOrder(Order) returns (DispatchReceipt);
  rpc Ping(PingRequest) returns (PongReply);
}

message PingRequest { string nonce = 1; }
message PongReply { string nonce = 1; int64 server_time_ms = 2; }
WD_EOF_V2P
cat > main.go <<'WD_EOF_BR'
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"strings"

	"google.golang.org/grpc"
	pb "windlass.dispatch.v2/dispatch.v2"
)

var (
	port = flag.Int("port", 50333, "port to listen on")
)

func addrSlug(raw string) string {
	return strings.ReplaceAll(strings.ToLower(strings.TrimSpace(raw)), " ", "-")
}

func weightClass(grams int32) string {
	if grams >= 10000 {
		return "heavy"
	}
	return "light"
}

func packagingFor(order *pb.Order) (string, string) {
	if b := order.GetBox(); b != nil {
		return fmt.Sprintf("box%d-%d-%d", b.GetWidthMm(), b.GetHeightMm(), b.GetDepthMm()), "box"
	}
	if e := order.GetEnvelope(); e != nil {
		return fmt.Sprintf("env%d", e.GetThicknessMm()), "envelope"
	}
	return "loose", "loose"
}

type dispatchServer struct {
	pb.UnimplementedDispatchServiceServer
}

func (s *dispatchServer) SubmitOrder(_ context.Context, in *pb.Order) (*pb.DispatchReceipt, error) {
	packaging, kind := packagingFor(in)
	out := &pb.DispatchReceipt{
		TrackingId:      in.GetTrackingId(),
		DeliveryAddress: in.GetDeliveryAddress(),
		RouteCode:       fmt.Sprintf("ROUTE:%s:%s:%s", packaging, weightClass(in.GetWeightGrams()), addrSlug(in.GetDeliveryAddress())),
		PackagingKind:   kind,
	}
	return out, nil
}

func (s *dispatchServer) Ping(_ context.Context, in *pb.PingRequest) (*pb.PongReply, error) {
	return &pb.PongReply{Nonce: in.GetNonce(), ServerTimeMs: 0}, nil
}

func main() {
	flag.Parse()
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("listen failed: %v", err)
	}
	svc := grpc.NewServer()
	pb.RegisterDispatchServiceServer(svc, &dispatchServer{})
	log.Printf("dispatch server listening on %v", lis.Addr())
	if err := svc.Serve(lis); err != nil {
		log.Fatalf("serve failed: %v", err)
	}
}
WD_EOF_BR
cat > client/client.py <<'WD_EOF_CL'
#!/usr/bin/env python3
"""Windlass DispatchService CLI client (schema v2).

Drives the running dispatch service over gRPC. Requires the python bindings
(next to this file, refreshed by `make gen`) and a running server.

Examples:
    python3 client.py --tracking ORD-7 --address "12 Dock Street" \\
        --instructions "FRAGILE" --weight 4000 --box 300x200x150
    python3 client.py --tracking ORD-8 --address "3 Quayside Wharf" \\
        --instructions "leave with porter" --weight 24000          # legacy shape
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import grpc  # noqa: E402

import dispatch_pb2 as pb  # noqa: E402
import dispatch_pb2_grpc as service  # noqa: E402


def build_order(args) -> pb.Order:
    order = pb.Order()
    order.tracking_id = args.tracking
    order.delivery_address = args.address
    if args.instructions is not None:
        order.special_instructions = args.instructions
    order.weight_grams = args.weight
    if args.box:
        w, h, d = [int(x) for x in args.box.split("x")]
        order.box.width_mm = w
        order.box.height_mm = h
        order.box.depth_mm = d
    elif args.envelope is not None:
        order.envelope.thickness_mm = args.envelope
    return order


def main():
    ap = argparse.ArgumentParser(description="Windlass dispatch client")
    ap.add_argument("--port", type=int, default=int(os.environ.get("DISPATCH_PORT", "50333")))
    ap.add_argument("--tracking", default="ORD-001")
    ap.add_argument("--address", default="12 Dock Street")
    ap.add_argument("--instructions", default="FRAGILE")
    ap.add_argument("--weight", type=int, default=4000)
    ap.add_argument("--box", default=None, help="WxHxD box dimensions in mm")
    ap.add_argument("--envelope", type=int, default=None, help="envelope thickness in mm")
    args = ap.parse_args()

    stub = service.DispatchServiceStub(
        grpc.insecure_channel("127.0.0.1:%d" % args.port))
    receipt = stub.SubmitOrder(build_order(args), timeout=20)
    print("tracking_id:      %s" % receipt.tracking_id)
    print("delivery_address: %s" % receipt.delivery_address)
    print("special_instr:    %r" % receipt.special_instructions)
    print("route_code:       %s" % receipt.route_code)
    print("packaging_kind:   %s" % receipt.packaging_kind)


if __name__ == "__main__":
    main()
WD_EOF_CL
cat > tests/e2e_test.py <<'WD_EOF_E2E'
"""Contract tests for the Windlass DispatchService.

These run against a LIVE server on 127.0.0.1:DISPATCH_PORT (default 50333).
Start one first, e.g.:

    make build && ./windlass-server --port=50333 &

Then:  python3 -m pytest tests -q
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "client"))

import grpc  # noqa: E402

import dispatch_pb2 as pb  # noqa: E402
import dispatch_pb2_grpc as service  # noqa: E402

PORT = int(os.environ.get("DISPATCH_PORT", "50333"))


def slug(addr):
    return " ".join(addr.strip().lower().split()).replace(" ", "-")


def new_conn():
    return service.DispatchServiceStub(
        grpc.insecure_channel("127.0.0.1:%d" % PORT))


def full_legacy_order():
    order = pb.Order()
    order.tracking_id = "E2E-LEGACY"
    order.delivery_address = "  41 Harbour Lane  "
    order.special_instructions = "by the fire escape"
    order.weight_grams = 26000
    return order


def full_box_order():
    order = pb.Order()
    order.tracking_id = "E2E-BOX"
    order.delivery_address = "12 Dock Street"
    order.special_instructions = "FRAGILE \u26a0 \U0001f69a"
    order.weight_grams = 4000
    order.box.width_mm = 300
    order.box.height_mm = 200
    order.box.depth_mm = 150
    return order


def full_env_order():
    order = pb.Order()
    order.tracking_id = "E2E-ENV"
    order.delivery_address = "9 Drawbridge Way"
    order.special_instructions = ""
    order.weight_grams = 120
    order.envelope.thickness_mm = 11
    return order


def test_legacy_shape_receipt():
    r = new_conn().SubmitOrder(full_legacy_order(), timeout=20)
    assert r.tracking_id == "E2E-LEGACY"
    assert r.delivery_address == "  41 Harbour Lane  "
    assert r.special_instructions == "by the fire escape"
    assert r.packaging_kind == "loose"
    assert r.route_code == "ROUTE:loose:heavy:41-harbour-lane"


def test_box_shape_receipt():
    r = new_conn().SubmitOrder(full_box_order(), timeout=20)
    assert r.tracking_id == "E2E-BOX"
    assert r.delivery_address == "12 Dock Street"
    assert r.special_instructions == "FRAGILE \u26a0 \U0001f69a"
    assert r.packaging_kind == "box"
    assert r.route_code == "ROUTE:box300-200-150:light:12-dock-street"


def test_envelope_shape_receipt():
    r = new_conn().SubmitOrder(full_env_order(), timeout=20)
    assert r.tracking_id == "E2E-ENV"
    assert r.special_instructions == ""
    assert r.packaging_kind == "envelope"
    assert r.route_code == "ROUTE:env11:light:9-drawbridge-way"
WD_EOF_E2E
git add -A && git commit -q -m 'Migrate DispatchService to the v2 schema'
# sanity: skip the build here on purpose; HEAD's bindings are stale and the
# Dockerfile's warm step uses a scratch clone instead.
rm -f /app/gen_repo.sh
echo REPO-GENERATED
git --no-pager log --oneline | head -8

