#!/bin/bash
# Oracle for cypress-lantern: writes the real HTTP client /app/light_beacon.py
# (challenge -> derive key -> POST payload -> print final), starts the beacon
# service, then RUNS the client on the default beacon delta-7 to produce
# /app/final_message.txt. Never reads /tests.
set -euo pipefail

BASE="http://127.0.0.1:8917"
CLIENT="/app/light_beacon.py"
OUT="/app/final_message.txt"

# 0. start the shipped service
if ! curl -sf "$BASE/api/announce" -o /dev/null 2>/dev/null; then
  (cd /app && python3 -m lantern_service.app >/tmp/lantern.log 2>&1) &
  for i in $(seq 1 60); do
    if curl -sf "$BASE/api/announce" -o /dev/null 2>/dev/null; then break; fi
    sleep 0.25
  done
fi
curl -sf "$BASE/api/announce" -o /dev/null || { echo "beacon service failed to start"; exit 1; }

# 1. write the deliverable client (real HTTP work, no canned answers).
cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""Light a cypress-lantern beacon: GET its challenge, derive the payload key
per the handbook formulas, POST it to the light route, print the final signal.

Exit 0 and print the final message on success; on any failure (unknown beacon,
rejected payload, unreachable service, missing argument) exit non-zero, print a
diagnostic to stderr, and never print a final message on stdout.
"""
import hashlib
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8917"


def get_json(url):
    with urllib.request.urlopen(url, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8")), resp.status


def post_json(url, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8")), resp.status


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: light_beacon.py <beacon_id>\n")
        return 2
    beacon_id = argv[1]
    try:
        ch, status = get_json("%s/api/beacon/%s/challenge" % (BASE, beacon_id))
    except urllib.error.HTTPError as e:
        sys.stderr.write("light_beacon: challenge failed with HTTP %d for '%s'\n"
                         % (e.code, beacon_id))
        return 1
    except Exception as e:
        sys.stderr.write("light_beacon: challenge request failed: %s\n" % e)
        return 1
    if status != 200 or "turn" not in ch:
        sys.stderr.write("light_beacon: beacon '%s' not registered\n" % beacon_id)
        return 1
    turn = ch["turn"]
    key = hashlib.sha256(("filament:" + turn).encode()).hexdigest()[:16]
    try:
        out, status = post_json(
            "%s/api/beacon/%s/light" % (BASE, beacon_id),
            {"turn": turn, "key": key})
    except urllib.error.HTTPError as e:
        sys.stderr.write("light_beacon: light failed with HTTP %d\n" % e.code)
        return 1
    except Exception as e:
        sys.stderr.write("light_beacon: light request failed: %s\n" % e)
        return 1
    if status != 200 or "final" not in out:
        sys.stderr.write("light_beacon: payload rejected for beacon '%s'\n" % beacon_id)
        return 1
    print(out["final"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$CLIENT"

# 2. run the client on the default beacon to produce the deliverable record.
python3 "$CLIENT" delta-7 > "$OUT"

echo "solve.sh done -> $CLIENT and $OUT"
cat "$OUT"
ls -l "$CLIENT" "$OUT"
