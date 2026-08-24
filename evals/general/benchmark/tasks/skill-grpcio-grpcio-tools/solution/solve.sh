#!/bin/bash
set -euo pipefail
mkdir -p /app/gen
cd /app
python3 -m grpc_tools.protoc --proto_path=/app --python_out=/app/gen --grpc_python_out=/app/gen /app/echo.proto
cat > /app/driver.py <<'DRIVER'
import sys
sys.path.insert(0, "/app/gen")
import echo_pb2 as pb2
import echo_pb2_grpc as pb2g

req = pb2.GreetRequest(name="atlantis")
data = req.SerializeToString()
req2 = pb2.GreetRequest()
req2.ParseFromString(data)
assert req2.name == "atlantis", req2.name
assert hasattr(pb2g, "GreetServiceStub")
open("/app/answer.txt", "w").write("OK")
print("OK")
DRIVER
python3 /app/driver.py