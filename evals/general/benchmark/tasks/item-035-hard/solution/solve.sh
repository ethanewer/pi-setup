#!/bin/bash
# Oracle solution for item-035-hard (gRPC KV with atomic batch + reset).
set -u
mkdir -p /app/proto /app/generated

cat > /app/proto/service.proto <<'PEOF'
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

message ResetRequest  { }
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
PEOF

cat > /app/server.py <<'PEOF'
#!/usr/bin/env python3
import os
import sys
import threading
import grpc
from concurrent import futures

BASE = "/app"
GEN = os.path.join(BASE, "generated")
os.makedirs(GEN, exist_ok=True)
sys.path.insert(0, GEN)


def compile_proto():
    from grpc_tools import protoc
    protoc.main([
        "grpc_tools.protoc",
        "--proto_path=" + os.path.join(BASE, "proto"),
        "--python_out=" + GEN,
        "--grpc_python_out=" + GEN,
        os.path.join(BASE, "proto", "service.proto"),
    ])


compile_proto()
import service_pb2 as pb2          # noqa: F401,E402
import service_pb2_grpc as pb2g    # noqa: E402

state = {}
lock = threading.Lock()


class KV(pb2g.KVStoreServicer):
    def Ping(self, req, ctx):
        return pb2.PingResponse(nonce=req.nonce)

    def Set(self, req, ctx):
        with lock:
            state[req.key] = req.value
        return pb2.SetResponse(ok=True)

    def Get(self, req, ctx):
        with lock:
            found = req.key in state
            v = state.get(req.key, 0)
        return pb2.GetResponse(found=found, value=v)

    def Inc(self, req, ctx):
        with lock:
            state[req.key] = state.get(req.key, 0) + req.delta
            v = state[req.key]
        return pb2.IncResponse(value=v)

    def MultiGet(self, req, ctx):
        with lock:
            out = {k: state.get(k, 0) for k in req.keys}
        return pb2.MultiGetResponse(values=out)

    def BatchInc(self, req, ctx):
        with lock:
            out = {}
            for k in req.keys:
                state[k] = state.get(k, 0) + req.delta
                out[k] = state[k]
        return pb2.BatchIncResponse(values=out)

    def Sum(self, req, ctx):
        with lock:
            total = sum(state.get(k, 0) for k in req.keys)
        return pb2.SumResponse(total=total)

    def Reset(self, req, ctx):
        with lock:
            cleared = len(state)
            state.clear()
        return pb2.ResetResponse(cleared=cleared)


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=256))
    pb2g.add_KVStoreServicer_to_server(KV(), server)
    server.add_insecure_port("127.0.0.1:50051")
    server.start()
    print("serving on 50051", flush=True)
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
PEOF

python3 /app/server.py > /app/server.log 2>&1 &

ok=0
for i in $(seq 1 60); do
  if python3 - <<'EOF' 2>/dev/null
import socket
try:
    s = socket.create_connection(("127.0.0.1", 50051), timeout=1); s.close(); print("UP"); exit(0)
except Exception:
    exit(1)
EOF
  then
    ok=1; break
  fi
  sleep 1
done

python3 - <<'EOF'
import sys, threading
sys.path.insert(0, "/app/generated")
import grpc
import service_pb2 as pb2
import service_pb2_grpc as pb2g
ch = grpc.insecure_channel("127.0.0.1:50051")
stub = pb2g.KVStoreStub(ch)
stub.Set(pb2.SetRequest(key="k", value=5))
g = stub.Get(pb2.GetRequest(key="k"))
assert g.value == 5 and g.found
def inc(_):
    stub.Inc(pb2.IncRequest(key="ct", delta=1))
ths = [threading.Thread(target=inc, args=(i,)) for i in range(80)]
for t in ths: t.start()
for t in ths: t.join()
gend = stub.Get(pb2.GetRequest(key="ct"))
assert gend.value == 80, gend.value
stub.Reset(pb2.ResetRequest())
print("self-check ok")
PY
exit 0