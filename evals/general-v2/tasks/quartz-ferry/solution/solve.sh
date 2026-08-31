#!/bin/bash
# Real oracle for quartz-ferry: write the client program, then RUN it against
# a live reference origin to produce /app/report.json. Never reads /tests.
set -eu

CLIENT="/app/client.py"
OUT="/app/report.json"

cat > "$CLIENT" <<'PY'
"""RelayGrid console CLI client: challenge -> login -> tasks -> logout."""
import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request


def sha256_hex(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def request_json(url, method="GET", body=None, headers=None, timeout=10):
    data = None
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


def load_passphrase(path):
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("passphrase:"):
                return line[len("passphrase:"):].strip()
    raise SystemExit("passfile missing 'passphrase:' line")


def derive_proof(challenge, passphrase, iterations):
    proof = sha256_hex(challenge + ":" + passphrase)
    for _ in range(iterations - 1):
        proof = sha256_hex(proof)
    return proof


def fail(msg):
    print("error: %s" % msg, file=sys.stderr)
    raise SystemExit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--origin", required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--passfile", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    origin = args.origin.rstrip("/")
    passphrase = load_passphrase(args.passfile)

    # 1) challenge
    status, body = request_json(origin + "/api/challenge")
    if status != 200 or "challenge" not in body:
        fail("challenge step failed")
    challenge = body["challenge"]
    iterations = int(body.get("iterations", 1))

    # 2) login
    proof = derive_proof(challenge, passphrase, iterations)
    status, body = request_json(
        origin + "/api/login", method="POST",
        body={"user": args.user, "challenge": challenge, "proof": proof},
        headers={"X-Client": "grid-cli"},
    )
    if status != 200 or "session" not in body:
        fail("login failed (status %s)" % status)
    token = body["session"]

    # 3) authenticated work
    auth = {"Authorization": "Bearer " + token}
    status, body = request_json(origin + "/api/tasks", headers=auth)
    if status != 200 or "tasks" not in body:
        fail("tasks step failed")
    tasks_count = len(body["tasks"])

    # 4) clean logout
    status, body = request_json(origin + "/api/logout", method="POST",
                                headers=auth)
    if status != 200 or body.get("logged_out") is not True:
        fail("logout failed")

    report = {
        "user": args.user,
        "challenge_used": challenge,
        "session_token": token,
        "tasks_count": tasks_count,
        "logged_out": True,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$CLIENT"

# Run the client against a live reference origin to produce the artifact.
PORT=20085
AUDIT="/tmp/quartz_ferry_ref_audit.jsonl"
rm -f "$AUDIT"
python3 /app/relayd.py --config /app/ref_scenario.json --port "$PORT" --audit "$AUDIT" &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null; wait $SRV_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  if python3 - <<'PROBE' 2>/dev/null
import urllib.request, sys
try:
    urllib.request.urlopen("http://127.0.0.1:20085/api/challenge", timeout=0.5)
except Exception:
    sys.exit(1)
sys.exit(0)
PROBE
  then break; fi
  sleep 0.2
done

python3 "$CLIENT" --origin "http://127.0.0.1:$PORT" \
                  --user grid-user --passfile /app/ref_passfile.txt \
                  --out "$OUT"

echo "solve.sh done -> $CLIENT and $OUT"
ls -l "$CLIENT" "$OUT"
