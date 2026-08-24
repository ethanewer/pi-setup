#!/bin/bash
# Oracle solution for item-035-main.
# Writes the wire contract and the gRPC server, starts it, and self-verifies.
set -u
mkdir -p /app/proto /app/generated

# 1) wire contract
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

service KVStore {
  rpc Ping    (PingRequest)    returns (PingResponse);
  rpc Set     (SetRequest)     returns (SetResponse);
  rpc Get     (GetRequest)     returns (GetResponse);
  rpc Inc     (IncRequest)     returns (IncResponse);
  rpc MultiGet(MultiGetRequest) returns (MultiGetResponse);
}
PEOF

# 2 server
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
    args = [
        "grpc_tools.protoc",
        "--proto_path=" + os.path.join(BASE, "proto"),
        "--python_out=" + GEN,
        "--grpc_python_out=" + GEN,
        os.path.join(BASE, "proto", "service.proto"),
    ]
    protoc.main(args)


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
        out = {}
        with lock:
            for k in req.keys:
                out[k] = state.get(k, 0)
        return pb2.MultiGetResponse(values=out)


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=128))
    pb2g.add_KVStoreServicer_to_server(KV(), server)
    port = server.add_insecure_port("127.0.0.1:50051")
    server.start()
    print("serving on 50051", flush=True)
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
PEOF

# start the server (leave it up)
python3 /app/server.py > /app/server.log 2>&1 &

# wait for readiness
ok=0
for i in $(seq 1 60); do
  if python3 - <<'EOF' 2>/dev/null
import socket
try:
    s=socket.create_connection(("127.0.0.1",50051),timeout=1); s.close(); print("UP"); exit(0)
except Exception: exit(1)
EOF
  then
    ok=1; break
  fi
  sleep 1
done

# self-check with a tiny client
python3 - <<'EOF'
import sys
sys.path.insert(0, "/app/generated")
import grpc
import service_pb2 as pb2
import service_pb2_grpc as pb2g
ch = grpc.insecure_channel("127.0.0.1:50051")
stub = pb2g.KVStoreStub(ch)
r = stub.Set(pb2.SetRequest(key="k", value=5))
g = stub.Get(pb2.GetRequest(key="k"))
assert g.value == 5 and g.found
print("self-check ok, server up")
EOF
exit 0