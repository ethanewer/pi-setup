#!/bin/bash
set -euo pipefail
cd /app
python3 -m grpc_tools.protoc --proto_path=/app --python_out=/app --grpc_python_out=/app /app/echo.proto
python3 /app/server.py &
sleep 1
cat > /app/client.py <<'CLIENT'
import grpc
import echo_pb2 as pb2
import echo_pb2_grpc as pb2g

channel = grpc.insecure_channel("127.0.0.1:50051")
stub = pb2g.GreetServiceStub(channel)
resp = stub.Greet(pb2.GreetRequest(name="neo"))
open("/app/answer.txt", "w").write(resp.message + "\n")
print(resp.message)
CLIENT
python3 /app/client.py
kill %1 2>/dev/null || true