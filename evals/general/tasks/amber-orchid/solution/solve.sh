#!/usr/bin/env bash
# Oracle for amber-orchid (Merkstock Index Ledger).
# Delivers the three artifacts into /app by WRITING the real implementation,
# then smoke-tests the API (import check + one live health request).
set -euo pipefail

cp /solution/api.py /app/api.py
cp /solution/schema.json /app/schema.json
cp /solution/xss.html /app/xss.html

# Sanity: the delivered service must import and boot in a fresh process.
python3 - <<'PY'
import subprocess, sys, time, urllib.request
port = 8124
p = subprocess.Popen([sys.executable, "/app/api.py", str(port)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(50):
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/api/v1/health" % port, timeout=2) as r:
                if r.status == 200:
                    print("oracle smoke: api up")
                    break
        except Exception:
            time.sleep(0.2)
    else:
        raise SystemExit("api did not become healthy during oracle smoke test")
finally:
    p.terminate()
    try:
        p.wait(timeout=5)
    except Exception:
        p.kill()
PY

echo "oracle artifacts delivered: /app/api.py /app/schema.json /app/xss.html"
