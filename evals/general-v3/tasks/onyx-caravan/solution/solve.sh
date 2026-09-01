#!/bin/bash
# Real oracle for onyx-caravan: write the session-client deliverable, then RUN
# it against the live reference origin to produce /app/answer.json.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Depot-operations session client: challenge-response login + clean logout."""
import argparse
import hashlib
import http.cookiejar
import json
import sys
import urllib.parse
import urllib.request


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--origin", required=True)
    ap.add_argument("--username", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    base = args.origin.rstrip("/")

    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def call(req):
        with opener.open(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))

    # 1. Challenge: read the nonce and the hash algorithm dynamically.
    challenge = call(base + "/challenge")
    nonce = challenge["nonce"]
    alg = challenge["alg"]
    token = hashlib.new(alg, (nonce + args.password).encode()).hexdigest()

    # 2. Login. Sending X-Nonce unconditionally is harmless on deployments
    #    that do not require it, and satisfies those that do.
    body = urllib.parse.urlencode({
        "username": args.username,
        "password": args.password,
        "token": token,
        "nonce": nonce,
    }).encode()
    req = urllib.request.Request(
        base + "/login", data=body, headers={"X-Nonce": nonce}
    )
    login = call(req)
    sid = login["sid"]

    # 3. Authenticated panel: cookie jar carries the session automatically.
    panel = call(base + "/panel")
    csrf = panel["csrf"]

    # 4. Clean, CSRF-protected logout.
    body = urllib.parse.urlencode({"csrf": csrf}).encode()
    logout = call(urllib.request.Request(base + "/logout", data=body))

    report = {
        "username": args.username,
        "logged_in": True,
        "sid": sid,
        "csrf": csrf,
        "logged_out": bool(logout.get("logged_out")),
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# ---- 2. Launch the reference origin and run the client against it.
PORT="${ORACLE_PORT:-20115}"
python3 /app/origin.py /app/config.json "$PORT" &
ORIGIN_PID=$!
trap 'kill "$ORIGIN_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
    if python3 -c "import socket,sys; s=socket.create_connection(('127.0.0.1',$PORT),1); s.close()" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

python3 "$SOLVER" --origin "http://127.0.0.1:$PORT" \
    --username cartwright --password landing-gear-7 \
    --out "$OUT"

kill "$ORIGIN_PID" 2>/dev/null || true
trap - EXIT

echo "solve.sh done -> $SOLVER and $OUT"
cat "$OUT"
