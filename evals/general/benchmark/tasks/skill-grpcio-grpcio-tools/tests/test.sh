#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/gen/echo_pb2.py ] && [ -f /app/gen/echo_pb2_grpc.py ]; then
  if python3 - <<'PYEOF'
import sys
sys.path.insert(0, "/app/gen")
import echo_pb2 as pb2
import echo_pb2_grpc as pb2g

req = pb2.GreetRequest(name="atlantis")
data = req.SerializeToString()
req2 = pb2.GreetRequest()
req2.ParseFromString(data)
ok = (req2.name == "atlantis") and hasattr(pb2g, "GreetServiceStub") and open("/app/answer.txt").read().strip() == "OK"
sys.exit(0 if ok else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt