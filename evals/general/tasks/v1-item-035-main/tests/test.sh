#!/bin/bash
# Verifier for item-035-main (gRPC KV server).
set -u
mkdir -p /logs/verifier

for f in /app/proto/service.proto /app/server.py; do
  if [ ! -f "$f" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
  fi
done

score=$(python3 - <<'EOF'
import grpc, os, socket, subprocess, sys, threading, time, uuid

STATE = {"score": 0.0}

def port_up():
    try:
        s = socket.create_connection(("127.0.0.1", 50051), timeout=1); s.close(); return True
    except Exception:
        return False

def validate():
    if not port_up():
        subprocess.Popen([sys.executable, "/app/server.py"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        end = time.time() + 60
        while time.time() < end and not port_up():
            time.sleep(0.5)
    if not port_up():
        return

    VB = "/tmp/kvstubs"
    os.makedirs(VB, exist_ok=True)
    from grpc_tools import protoc
    protoc.main([
        "grpc_tools.protoc",
        "--proto_path=/app/proto",
        "--python_out=" + VB,
        "--grpc_python_out=" + VB,
        "/app/proto/service.proto",
    ])
    sys.path.insert(0, VB)
    import service_pb2 as pb2          # noqa: E402
    import service_pb2_grpc as pb2g    # noqa: E402

    channel = grpc.insecure_channel("127.0.0.1:50051")
    stub = pb2g.KVStoreStub(channel)
    ns = uuid.uuid4().hex[:8]
    v = 0.0

    try:
        nonce = ns + "-hello"
        if stub.Ping(pb2.PingRequest(nonce=nonce), timeout=20).nonce == nonce:
            v += 0.2
    except Exception:
        pass

    try:
        ka = ns + "_a"
        stub.Set(pb2.SetRequest(key=ka, value=10), timeout=20)
        g = stub.Get(pb2.GetRequest(key=ka), timeout=20)
        gmiss = stub.Get(pb2.GetRequest(key=ns + "_miss"), timeout=20)
        if g.found and g.value == 10 and not gmiss.found:
            v += 0.2
    except Exception:
        pass

    try:
        ka = ns + "_a"
        r1 = stub.Inc(pb2.IncRequest(key=ka, delta=5), timeout=20)
        r2 = stub.Inc(pb2.IncRequest(key=ka, delta=7), timeout=20)
        mg = stub.MultiGet(pb2.MultiGetRequest(keys=[ka, ns + "_b"]), timeout=20)
        if r1.value == 15 and r2.value == 22 and mg.values.get(ka) == 22 and mg.values.get(ns + "_b") == 0:
            v += 0.2
    except Exception:
        pass

    try:
        ck = "ctr_" + ns
        def inc_one(_):
            try:
                stub.Inc(pb2.IncRequest(key=ck, delta=1), timeout=30)
            except Exception:
                pass
        ths = [threading.Thread(target=inc_one, args=(i,)) for i in range(30)]
        for t in ths: t.start()
        for t in ths: t.join()
        gend = stub.Get(pb2.GetRequest(key=ck), timeout=20)
        if gend.found and gend.value == 30:
            v += 0.4
        elif gend.found and gend.value >= 28:
            v += 0.25
    except Exception:
        pass

    STATE["score"] = round(v, 2)

try:
    validate()
except Exception:
    pass
print(f"{STATE['score']:.2f}", end="")
EOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"