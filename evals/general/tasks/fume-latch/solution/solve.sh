#!/bin/bash
# Oracle for fume-latch: write the generic repair client, start the visible
# desk session, run the client against it, and persist the receipt. Never
# reads /tests.
set -eu

CLIENT="/app/apply_fixes.py"
RECEIPT="/app/receipt.json"
PORT=8471

# ---- 1. The generic client: one fix per work-order entry, then commit.
cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""Fume Latch repair client: submits exactly one fix request per work-order
entry against the desk service, then commits and persists the receipt.

Usage:
  python3 apply_fixes.py --url http://127.0.0.1:PORT \
      --order work_order.json --receipt out.json
"""
import argparse
import json
import sys
import urllib.error
import urllib.request


def call(url, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if payload is not None else "GET",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8")), r.status


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--order", required=True)
    ap.add_argument("--receipt", required=True)
    args = ap.parse_args()
    base = args.url.rstrip("/")

    with open(args.order, "r", encoding="utf-8") as f:
        order = json.load(f)

    session = call(base + "/api/session")[0]
    receipt = {"order_id": order.get("order_id"),
               "session": session.get("session"),
               "budget": session.get("budget")}

    # Exactly one fix request per work-order entry: the budget is sized to the
    # order, so any extra request would flip the session to budget-exceeded.
    for entry in order.get("fixes", []):
        try:
            resp, code = call(base + "/api/fix",
                              {"line": entry["line"], "content": entry["content"]})
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")
            print("fix request failed (%d): %s" % (e.code, detail), file=sys.stderr)
            receipt["status"] = "budget-exceeded" if e.code == 409 else "error"
            receipt["all_fixed"] = False
            _write(args.receipt, receipt)
            return 1
        receipt["fixes_used"] = resp.get("fixes_used")
        receipt["budget"] = resp.get("budget")

    try:
        commit, _ = call(base + "/api/commit", {})
    except urllib.error.HTTPError as e:
        print("commit failed: %s" % e.read().decode("utf-8", "replace"), file=sys.stderr)
        return 1
    receipt.update(commit)
    _write(args.receipt, receipt)

    if not receipt.get("all_fixed") or receipt.get("status") != "open":
        print("session not clean: %s" % json.dumps(receipt), file=sys.stderr)
        return 1
    print("receipt ok: %s" % json.dumps(
        {k: receipt[k] for k in ("session", "all_fixed", "fixes_used",
                                 "budget", "status")}))
    return 0


def _write(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$CLIENT"

# ---- 2. Start the visible desk session and run the client against it.
python3 /app/desk_service.py --serve --port "$PORT" --case /app/desk/visible_case.json &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1
python3 "$CLIENT" --url "http://127.0.0.1:$PORT" \
    --order /app/work_order.json --receipt "$RECEIPT"
kill "$SRV" 2>/dev/null || true
trap - EXIT

echo "solve.sh done -> $CLIENT and $RECEIPT"
cat "$RECEIPT"
