#!/bin/bash
# Oracle for basalt-quay: write the client program, start the visible planner
# session, run the client against it to produce /app/plans.jsonl.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/plans.jsonl"
PORT=8731
SVC_OUT="/tmp/oracle_visible_out.jsonl"

# ---- 1. Write the deliverable client (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Harborline planner client: page all requests, plan each, commit."""
import argparse
import json
import sys
import urllib.request

VCPU_PER = {"basic": 1, "standard": 2, "performance": 4}
MEM_GIB_PER = {"basic": 2, "standard": 4, "performance": 8}


def get_json(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def post_json(url, obj):
    data = json.dumps(obj).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def shape_for(req):
    gpu = bool(req.get("gpu", False))
    return {
        "vcpus": VCPU_PER[req["tier"]] * req["replicas"] + (8 if gpu else 0),
        "memory_gib": MEM_GIB_PER[req["tier"]] * req["replicas"],
        "disk_gib": max(16, ((int(req["storage_gb"]) + 15) // 16) * 16),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--receipt")
    args = ap.parse_args()
    base = args.url.rstrip("/")

    sess = get_json(base + "/api/session")
    total = int(sess["total"])

    requests = []
    offset = 0
    while len(requests) < total:
        page = get_json("%s/api/requests?offset=%d&limit=40" % (base, offset))
        batch = page["requests"]
        if not batch:
            break
        requests.extend(batch)
        offset += len(batch)

    if len(requests) != total:
        sys.stderr.write("fetched %d of %d requests\n" % (len(requests), total))
        sys.exit(1)

    records = []
    for req in requests:
        rec = {"id": req["id"], "batch": req["batch"], "shape": shape_for(req)}
        resp = post_json(base + "/api/plan", rec)
        if not resp.get("ok"):
            sys.stderr.write("plan rejected for %s: %r\n" % (rec["id"], resp))
            sys.exit(1)
        records.append(rec)

    receipt = post_json(base + "/api/commit", {})
    if not receipt.get("committed"):
        sys.stderr.write("commit failed: %r\n" % receipt)
        sys.exit(1)

    with open(args.out, "w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec, separators=(",", ":")) + "\n")
    if args.receipt:
        with open(args.receipt, "w", encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=2)
            fh.write("\n")


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# ---- 2. Run the client on the visible session to produce the deliverable.
rm -f "$OUT" "$SVC_OUT"
python3 /app/planner_service.py --serve --port "$PORT" \
    --case /app/planner/visible_case.json --out "$SVC_OUT" &
SVC_PID=$!
trap 'kill "$SVC_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 100); do
    if python3 -c "import urllib.request,json;json.load(urllib.request.urlopen('http://127.0.0.1:$PORT/api/session',timeout=2))" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

python3 "$SOLVER" --url "http://127.0.0.1:$PORT" --out "$OUT" \
    --receipt /app/receipt.json

kill "$SVC_PID" 2>/dev/null || true
wait "$SVC_PID" 2>/dev/null || true
trap - EXIT

echo "solve.sh done -> $SOLVER and $OUT"
wc -l "$OUT"
