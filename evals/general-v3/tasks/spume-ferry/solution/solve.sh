#!/bin/bash
# Real oracle for spume-ferry: write the claim script, start the service, run
# the claim flow for dock 21, and produce all deliverables. Never reads /tests.
set -eu

SCRIPT="/app/claim_pass.py"
MSG="/app/final_message.txt"
RECEIPT="/app/claim_receipt.json"

cat > "$SCRIPT" <<'PY'
#!/usr/bin/env python3
"""Claim a spume-ferry pier pass by POSTing the rendezvous payload."""
import hashlib
import json
import os
import sys
import urllib.request

PORT = os.environ.get("FERRY_PORT", "8652")
BASE = "http://127.0.0.1:%s" % PORT
RECEIPT_PATH = "/app/claim_receipt.json"


def main():
    if len(sys.argv) != 2:
        print("usage: claim_pass.py <dock_id>", file=sys.stderr)
        return 2
    try:
        dock = int(sys.argv[1])
    except ValueError:
        print("error: dock id must be an integer, got %r" % sys.argv[1],
              file=sys.stderr)
        return 2

    nonce = (dock * 13 + 11) % 1000000
    digest = hashlib.sha256(("spume:%d" % nonce).encode("utf-8")).hexdigest()
    body = json.dumps({"tide": digest[0:12],
                       "slip": int(digest[0:8], 16) % 9000 + 1000}).encode()

    req = urllib.request.Request(
        BASE + "/api/v1/claim", data=body, method="POST",
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        print("error: claim failed for dock %d: %s" % (dock, exc),
              file=sys.stderr)
        return 1
    if not isinstance(payload, dict) or "final" not in payload:
        print("error: no receipt matches dock %d" % dock, file=sys.stderr)
        return 1

    with open(RECEIPT_PATH, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
    print(payload["final"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$SCRIPT"

# Start the service if it is not already up, then run the claim for dock 21.
if ! curl -sf http://127.0.0.1:8652/api/v1/announce -o /dev/null 2>/dev/null; then
  (cd /app && python3 -m ferry_app.app >/tmp/ferry.log 2>&1) &
  FERRY_PID=$!
  for i in $(seq 1 60); do
    curl -sf http://127.0.0.1:8652/api/v1/announce -o /dev/null 2>/dev/null && break
    sleep 0.25
  done
fi

python3 "$SCRIPT" 21 > "$MSG"

echo "solve.sh done -> $SCRIPT $MSG $RECEIPT"
ls -l "$SCRIPT" "$MSG" "$RECEIPT"
cat "$MSG"
