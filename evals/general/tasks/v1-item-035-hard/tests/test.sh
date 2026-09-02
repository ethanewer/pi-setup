#!/bin/bash
# Verifier for item-035-hard: run every RPC path incl. batch atomicity, reset.
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
            v += 0.1
    except Exception:
        pass

    try:
        ka = ns + "_a"
        stub.Set(pb2.SetRequest(key=ka, value=10), timeout=20)
        g = stub.Get(pb2.GetRequest(key=ka), timeout=20)
        gmiss = stub.Get(pb2.GetRequest(key=ns + "_miss"), timeout=20)
        if g.found and g.value == 10 and not gmiss.found:
            v += 0.1
    except Exception:
        pass

    try:
        ka = ns + "_a"
        r1 = stub.Inc(pb2.IncRequest(key=ka, delta=5), timeout=20)
        r2 = stub.Inc(pb2.IncRequest(key=ka, delta=7), timeout=20)
        mg = stub.MultiGet(pb2.MultiGetRequest(keys=[ka, ns + "_b"]), timeout=20)
        if r1.value == 15 and r2.value == 22 and mg.values.get(ka) == 22 and mg.values.get(ns + "_b") == 0:
            v += 0.1
    except Exception:
        pass

    try:
        ck = "ctr_" + ns
        def inc_one(_):
            try:
                stub.Inc(pb2.IncRequest(key=ck, delta=1), timeout=30)
            except Exception:
                pass
        ths = [threading.Thread(target=inc_one, args=(i,)) for i in range(80)]
        for t in ths: t.start()
        for t in ths: t.join()
        gend = stub.Get(pb2.GetRequest(key=ck), timeout=20)
        if gend.found and gend.value == 80:
            v += 0.25
        elif gend.found and gend.value >= 76:
            v += 0.1
    except Exception:
        pass

    try:
        kx = "mix_" + ns
        def inc_i(_):
            try: stub.Inc(pb2.IncRequest(key=kx, delta=1), timeout=30)
            except Exception: pass
        def batch_i(_):
            try: stub.BatchInc(pb2.BatchIncRequest(keys=[kx], delta=1), timeout=30)
            except Exception: pass
        ths = [threading.Thread(target=inc_i, args=(i,)) for i in range(20)]
        thb = [threading.Thread(target=batch_i, args=(i,)) for i in range(20)]
        for t in ths + thb: t.start()
        for t in ths + thb: t.join()
        gx = stub.Get(pb2.GetRequest(key=kx), timeout=20)
        if gx.found and gx.value == 40:
            v += 0.25
        elif gx.found and gx.value >= 38:
            v += 0.1
    except Exception:
        pass

    try:
        b1 = stub.BatchInc(pb2.BatchIncRequest(keys=[ns + "_p", ns + "_q"], delta=3), timeout=20)
        s = stub.Sum(pb2.SumRequest(keys=[ns + "_p", ns + "_q", ns + "_z"]), timeout=20)
        if b1.values.get(ns + "_p") == 3 and b1.values.get(ns + "_q") == 3 and s.total == 6:
            v += 0.1
    except Exception:
        pass

    try:
        stub.Set(pb2.SetRequest(key=ns + "_r", value=1), timeout=20)
        r = stub.Reset(pb2.ResetRequest(), timeout=20)
        g = stub.Get(pb2.GetRequest(key=ns + "_r"), timeout=20)
        if r.cleared >= 1 and not g.found:
            v += 0.1
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