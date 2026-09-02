#!/bin/bash
# calm-jetty oracle. Starts the local cloud emulator, then does the FULL job the
# agent must do: writes every deliverable under /app and RUNS it to produce the
# JSON artifacts. Never reads /tests.
set -euo pipefail
cd /app

CLOUD_PORT=8791
CLOUD_BASE="http://127.0.0.1:${CLOUD_PORT}"
export CLOUD_BASE

# --------------------------------------------------------------------- start
python3 /app/cloudsvc.py --store /app/store --port "$CLOUD_PORT" &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1

# 1. bucket public-read policy ----------------------------------------------
cat > /app/bucket_policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicGetReports",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::reports/*"
    }
  ]
}
JSON
python3 - "$CLOUD_BASE" <<'PY'
import json, sys, urllib.request
base = sys.argv[1]
pol = json.load(open("/app/bucket_policy.json"))
req = urllib.request.Request(base + "/blob/v2/buckets/reports/policy",
                             data=json.dumps(pol).encode(), method="PUT")
req.add_header("Content-Type", "application/json")
with urllib.request.urlopen(req) as resp:
    assert resp.status == 200, resp.status
print("bucket_policy applied")
PY

# 2. Sheets client ------------------------------------------------
cat > /app/sheets_client.py <<'PY'
#!/usr/bin/env python3
"""calm-jetty Sheets REST client: create a spreadsheet and a worksheet,
persisting the returned identifiers."""
import json
import os
import urllib.request

BASE = os.environ.get("CLOUD_BASE", "http://127.0.0.1:8791")
OUT = os.environ.get("SHEET_RESULT", "/app/sheet_ids.json")
DEFAULT_NAME = "quarterly-updates-2025"
DEFAULT_TITLE = "scorecard-by-stage"


def _http(method, base, path, payload=None):
    url = base.rstrip("/") + path
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8")
        return resp.status, (json.loads(body) if body else {})


def create_spreadsheet(base=BASE, name=DEFAULT_NAME):
    """POST /sheets/v1 -> {"spreadsheet_id","name"}"""
    _, body = _http("POST", base, "/sheets/v1", {"name": name})
    return body


def create_worksheet(base=BASE, spreadsheet_id=None, title=DEFAULT_TITLE):
    """POST /sheets/v1/{sid}/sheets -> {"sheet_id","title"}"""
    if not spreadsheet_id:
        raise ValueError("spreadsheet_id is required")
    _, body = _http("POST", base, "/sheets/v1/%s/sheets" % spreadsheet_id,
                    {"title": title})
    return body


def main():
    sp = create_spreadsheet()
    sp_id = sp["spreadsheet_id"]
    ws = create_worksheet(spreadsheet_id=sp_id)
    with open(OUT, "w") as fh:
        json.dump({"spreadsheet_id": sp_id, "sheet_id": ws["sheet_id"]}, fh, indent=2)
    print("wrote %s" % OUT)


if __name__ == "__main__":
    main()
PY
chmod +x /app/sheets_client.py
python3 /app/sheets_client.py

# 3. RPC normalizer ------------------------------------------------
cat > /app/normalize_rpc.py <<'PY'
#!/usr/bin/env python3
"""calm-jetty RPC normalizer: translate raw gateway responses into the flat
JSON schema the downstream warehouse consumes."""
import json


def _to_int(v):
    if v is None:
        return None
    try:
        return int(float(str(v).strip()))
    except Exception:
        return None


def _normalize_one(raw):
    """Map one raw RPC response dict into the flat normalized schema."""
    if not isinstance(raw, dict):
        raw = {}
    reqid = raw.get("request_id")
    reqid = str(reqid) if reqid is not None else ""
    lookup = raw.get("lookup") if isinstance(raw.get("lookup"), dict) else {}
    contact = lookup.get("contact") if isinstance(lookup.get("contact"), dict) else {}
    ent = lookup.get("entitlement") if isinstance(lookup.get("entitlement"), dict) else {}
    bud = lookup.get("budget") if isinstance(lookup.get("budget"), dict) else {}
    grd = lookup.get("guardrail") if isinstance(lookup.get("guardrail"), dict) else {}

    aid = str(lookup.get("account_id")) if lookup.get("account_id") is not None else ""
    handle = str(lookup.get("handle")) if lookup.get("handle") is not None else ""

    email = contact.get("email")
    email = email if isinstance(email, str) and email.strip() else None
    region = contact.get("market")
    region = region if isinstance(region, str) else None

    tier = ent.get("tier")
    tier = str(tier).strip().lower() if tier is not None else None

    aware = grd.get("aware")
    active = aware if isinstance(aware, bool) else None

    return {
        "request_id": reqid,
        "account_id": aid,
        "handle": handle,
        "email": email,
        "region": region,
        "tier": tier,
        "storage_gb": _to_int(bud.get("storage_gb")),
        "breach": _to_int(bud.get("breach")),
        "active": active,
    }


def normalize_rpc(raws):
    """Normalize a list of raw responses (or a single raw dict) to the flat
    schema. Returns a list of normalized dicts, or one dict for one input."""
    single = isinstance(raws, dict)
    items = [raws] if single else list(raws)
    out = [_normalize_one(x) for x in items]
    return out[0] if single and out else out


def main():
    raw = json.load(open("/app/sample_rpc.json"))
    out = normalize_rpc(raw)
    with open("/app/rpc_normalized.json", "w") as fh:
        json.dump({"cases": out}, fh, indent=2)
    print("wrote /app/rpc_normalized.json (%d cases)" % len(out))


if __name__ == "__main__":
    main()
PY
chmod +x /app/normalize_rpc.py
python3 /app/normalize_rpc.py

# 4. account deletion ----------------------------------------------
cat > /app/delete_users.py <<'PY'
#!/usr/bin/env python3
"""calm-jetty identity client: delete exactly the targeted accounts, then emit a
snapshot of the survivors. Non-target accounts must remain present."""
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get("CLOUD_BASE", "http://127.0.0.1:8791")


def _http(method, base, path):
    req = urllib.request.Request(base.rstrip("/") + path, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8")
        return resp.status, (json.loads(body) if body else {})


def delete_account(base, uid):
    try:
        status, _ = _http("DELETE", base, "/identity/v2/accounts/" + uid)
        return status == 200
    except urllib.error.HTTPError:
        return False


def delete_targets(base, targets):
    """Delete exactly the listed user ids; return the ids that were removed."""
    return [t for t in targets if delete_account(base, t)]


def list_accounts(base):
    _, body = _http("GET", base, "/identity/v2/accounts")
    return body.get("accounts", [])


def main():
    targets = json.load(open("/app/delete_targets.json"))["targets"]
    deleted = delete_targets(BASE, targets)
    remaining = list_accounts(BASE)
    with open("/app/users_remaining.json", "w") as fh:
        json.dump({"deleted_targets": sorted(deleted),
                   "accounts_remaining": remaining}, fh, indent=2)
    print("deleted %d targets, %d accounts remain" % (len(deleted), len(remaining)))


if __name__ == "__main__":
    main()
PY
chmod +x /app/delete_users.py
python3 /app/delete_users.py

echo "calm-jetty deliverables produced OK" >&2
exit 0