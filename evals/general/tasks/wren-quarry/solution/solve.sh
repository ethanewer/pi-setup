#!/bin/bash
# Oracle for wren-quarry: start the defect-service, read the defect report
# over HTTP, and send exactly one well-aimed fix request per defect line
# through POST /fix (5 attempts, within both the 8-attempt service budget and
# the grader's 6-attempt ceiling).  Never reads /tests.
set -eu

PORT=8710
SERVER="/app/ops/defect_server.py"
STATE="/app/ops/state.json"

rm -f "$STATE"

# 1. Start the service in the background and wait for it to listen.
nohup python3 "$SERVER" --port "$PORT" >/tmp/defect_server.log 2>&1 &
SRV_PID=$!
for _ in $(seq 1 50); do
  if python3 - <<PY
import socket, sys
s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", $PORT)); sys.exit(0)
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
  then break; fi
  sleep 0.2
done

# 2. One POST /fix per defect line. The pristine repairs are derived from the
#    documented contract of each function (see the module docstrings).
python3 - "$PORT" <<'PY'
import json, sys, urllib.request

port = int(sys.argv[1])
base = "http://127.0.0.1:%d" % port

report = json.load(urllib.request.urlopen(base + "/defects", timeout=10))
by_kind = {d["id"]: d for d in report["defects"]}

# id -> exact replacement line (restores the documented contract)
FIXES = {
    "d1": "        acc += v",
    "d2": "    for i in range(len(values) - window + 1):",
    "d3": "    return [min(max(v, lo), hi) for v in values]",
    "d4": "    return [values[i:i + n] for i in range(0, len(values), n)]",
    "d5": "    return sorted(values, reverse=True)[:k]",
}

order = ["d1", "d2", "d3", "d4", "d5"]
for did in order:
    d = by_kind[did]
    body = json.dumps({"line": d["line"], "content": FIXES[did]}).encode()
    req = urllib.request.Request(base + "/fix", data=body,
                                 headers={"Content-Type": "application/json"})
    resp = json.load(urllib.request.urlopen(req, timeout=10))
    assert resp.get("ok") and resp.get("applied"), resp
    print("fixed", did, "line", d["line"], "fixes_used", resp["fixes_used"])
assert json.load(urllib.request.urlopen(base + "/status", timeout=10))["fixes_used"] == 5
PY

# 3. Sanity: the repaired module must satisfy the visible examples.
python3 - <<'PY'
import importlib.util, json

spec = importlib.util.spec_from_file_location("rectify", "/app/pipeline/rectify.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
cases = json.load(open("/app/pipeline/examples.json"))["cases"]
for c in cases:
    got = getattr(mod, c["func"])(*c["args"])
    assert got == c["expect"], (c, got)
print("visible examples: all pass")
PY

kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true

echo "oracle done"
ls -l /app/pipeline/rectify.py "$STATE"
