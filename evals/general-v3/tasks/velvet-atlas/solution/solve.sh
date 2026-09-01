#!/bin/bash
# Real oracle for velvet-atlas: write the generic client module, start the
# emulator on the seeded store, run the client to perform the API deletions,
# then stop the emulator. Never reads /tests.
set -eu

CLIENT="/app/deactivate.py"
OUT="/app/remaining.json"

cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""velvet-atlas attendee deactivation client (generic, stdlib only)."""
import json
import os
import sys
import time
import urllib.error
import urllib.request


def _request(method, url):
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        return exc.code, (json.loads(body) if body else {})


def list_attendees(base):
    """Return the current attendees array from GET /api/v1/attendees."""
    status, body = _request("GET", base.rstrip("/") + "/api/v1/attendees")
    if status != 200:
        raise RuntimeError("GET attendees failed with status %d" % status)
    return body.get("attendees", [])


def cancel_attendees(base, ids):
    """DELETE exactly the listed attendee IDs; return the IDs actually removed.

    Skips IDs that are already absent (404) rather than failing.
    """
    removed = []
    for aid in ids:
        status, _ = _request(
            "DELETE", base.rstrip("/") + "/api/v1/attendees/" + str(aid))
        if status == 200:
            removed.append(str(aid))
        elif status == 404:
            continue
        else:
            raise RuntimeError("DELETE %s failed with status %d" % (aid, status))
    return removed


def main():
    base = os.environ.get("BADGEDESK_BASE", "http://127.0.0.1:8841")
    with open("/app/cancel_list.json") as fh:
        targets = json.load(fh)["cancel"]

    removed = cancel_attendees(base, targets)
    remaining = list_attendees(base)
    with open("/app/remaining.json", "w") as fh:
        json.dump({"removed": removed, "remaining": remaining}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$CLIENT"

# Start the emulator on the seeded store, run the client, stop the emulator.
python3 /app/badgedesk.py --store /app/store --port 8841 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
    if python3 -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8841/health', timeout=1)" 2>/dev/null; then
        break
    fi
    sleep 0.2
done
python3 "$CLIENT"
kill $SRV 2>/dev/null || true
wait $SRV 2>/dev/null || true
trap - EXIT

echo "solve.sh done -> $CLIENT and $OUT"
ls -l "$CLIENT" "$OUT"
