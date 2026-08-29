#!/usr/bin/env python3
"""cloudsvc — a small, self-contained local cloud emulator (blob / sheets /
identity) used by the calm-jetty scenario.

It exposes a handful of REST-style endpoints over HTTP. All state persists as
JSON files under a single store directory (default /app/store). An append-only
"audit.ndjson" records the operations that were performed so the harness can
confirm work was done through the API and not by editing state files directly.

Run it with:
    python3 cloudsvc.py --store /app/store --port 8790

The store carries three JSON documents:

  blob.json     {"buckets": {"reports": {"policy": <json|null>,
                                        "objects": ["key_a", ...]}}}
  sheets.json   {"spreadsheets": [{"spreadsheet_id", "name",
                                   "worksheets": [{"sheet_id","title"}], }]}
  identity.json {"accounts": [{"user_id","full_name","email"}]}

Endpoint map (all paths below are prefixed by the scheme+host):

  GET    /health
  GET    /blob/v2/buckets
  GET    /blob/v2/buckets/{bucket}
  PUT    /blob/v2/buckets/{bucket}/policy      (body = policy JSON)
  GET    /blob/v2/buckets/{bucket}/policy
  GET    /blob/v2/buckets/{bucket}/access?object={key}
  GET    /sheets/v1
  POST   /sheets/v1                             (body {"name": "..."})
  POST   /sheets/v1/{sid}/worksheets           (body {"title": "..."})
  GET    /sheets/v1/{sid}
  GET    /sheets/v1/{sid}/sheets/{wid}
  GET    /identity/v2/accounts
  GET    /identity/v2/accounts/{uid}
  DELETE /identity/v2/accounts/{uid}
"""
import argparse
import json
import os
import re
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote, parse_qs


def glob_match(pattern, value):
    """Minimal '*' wildcard matcher over the last path-ish segment."""
    if not isinstance(pattern, str):
        return False
    rx = re.compile(r"^" + re.escape(pattern).replace(r"\*", ".*") + r"$")
    return bool(rx.match(value))


def policy_allows_public_get(bucket, policy, object_key):
    """Return True if `policy` grants anonymous pubff s3:GetObject on the given
    object in `bucket`. This is the exact rule the harness's acceptance check
    uses. Principals may be "*" (string) or {"AWS": "*"}. Action may be a string
    or a list. Resource may be a string or a list; resource tokens may contain
    a single ``*`` wildcard."""
    if not isinstance(policy, dict):
        return False
    if not object_key:
        return False
    stmts = policy.get("Statement")
    if isinstance(stmts, dict):
        stmts = [stmts]
    if not isinstance(stmts, list):
        return False
    arn = "arn:aws:s3:::%s/%s" % (bucket, object_key)
    for s in stmts:
        if not isinstance(s, dict):
            continue
        if s.get("Effect") != "Allow":
            continue
        prin = s.get("Principal")
        if not (prin == "*" or (isinstance(prin, dict) and prin.get("AWS") == "*")):
            continue
        act = s.get("Action")
        actions = act if isinstance(act, list) else ([act] if act is not None else [])
        ok_action = any(
            (a == "*") or (isinstance(a, str) and a.lower() == "s3:getobject")
            for a in actions
        )
        if not ok_action:
            continue
        res = s.get("Resource")
        resources = res if isinstance(res, list) else ([res] if res is not None else [])
        if any(isinstance(r, str) and glob_match(r, arn) for r in resources):
            return True
    return False


class Store:
    """JSON-file-backed persistence under a single directory."""

    def __init__(self, root):
        self.root = root
        os.makedirs(root, exist_ok=True)

    def _path(self, name):
        return os.path.join(self.root, name)

    def read(self, name, default):
        p = self._path(name)
        if not os.path.exists(p):
            return default
        with open(p) as fh:
            return json.load(fh)

    def write(self, name, data):
        with open(self._path(name), "w") as fh:
            json.dump(data, fh, indent=2, sort_keys=False)

    def audit(self, entry):
        path = self._path("audit.ndjson")
        with open(path, "a") as fh:
            fh.write(json.dumps(entry) + "\n")


class Handler(BaseHTTPRequestHandler):
    store = None
    version = "1.0.0"

    def log_message(self, *a):
        pass

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _send(self, code, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _not_found(self, msg="not_found"):
        self._send(404, {"error": msg})

    # ------------------------------------------------------------- routing
    def _route(self, method):
        parsed = urlparse(self.path)
        path = unquote(parsed.path.rstrip("/"))
        args = parse_qs(parsed.query)
        if path == "/health" and method == "GET":
            return self._send(200, {"service": "halcyon-cloud", "version": self.version})

        # ---- blob -------------------------------------------------------
        if path.startswith("/blob/v2/"):
            return self._blob(method, path[len("/blob/v2/"):], args)
        # ---- sheets
        if path.startswith("/sheets/v1"):
            return self._sheets(method, path[len("/sheets/v1"):].lstrip("/"))
        # ---- identity
        if path.startswith("/identity/v2/"):
            return self._identity(method, path[len("/identity/v2/"):].lstrip("/"))
        self._notfound()

    # ----------------------------------------------------------------- blob
    def _blob(self, method, rest, args):
        blob = self.store.read("blob.json", {"buckets": {}})
        buckets = blob.setdefault("buckets", {})
        parts = rest.split("/")
        # parts: ["buckets"] or ["buckets", NAME, ...]
        if parts[0] != "buckets":
            return self._notfound()
        if len(parts) == 1:
            if method == "GET":
                return self._send(200, {"buckets": sorted(buckets.keys())})
            return self._notfound("method_not_allowed")
        name = parts[1]
        bucket = buckets.get(name)
        if len(parts) == 2:
            if method == "GET":
                if bucket is None:
                    return self._notfound("no_such_bucket")
                return self._send(200, {"bucket": name, "policy": bucket.get("policy"),
                                        "objects": bucket.get("objects", [])})
        if len(parts) == 3 and parts[2] == "policy":
            if method == "PUT":
                policy = self._body()
                b = bucket or {"policy": None, "objects": []}
                b["policy"] = policy
                buckets[name] = b
                self.store.write("blob.json", blob)
                self.store.audit({"op": "pod:put-policy", "bucket": name})
                return self._send(200, {"applied": True, "bucket": name})
            if method == "GET":
                if bucket is None:
                    return self._notfound("no_such_bucket")
                return self._send(200, {"bucket": name, "policy": bucket.get("policy")})
        if len(parts) == 3 and parts[2] == "access":
            if method == "GET":
                if bucket is None:
                    return self._notfound("no_such_bucket")
                object_key = (args.get("object") or [""])[0]
                allowed = policy_allows_public_get(name, bucket.get("policy"), object_key)
                return self._send(200, {"bucket": name, "object": object_key,
                                        "allowed": allowed,
                                        "reason": "public-GetObject" if allowed else "denied"})
        return self._notfound()

    # --------------------------------------------------------------- sheets
    def _sheets(self, method, rest):
        sheets = self.store.read("sheets.json", {"spreadsheets": []})
        spreadsheets = sheets.setdefault("spreadsheets", [])
        parts = [p for p in rest.split("/") if p]
        if len(parts) == 0:
            if method == "GET":
                return self._send(200, {"spreadsheets": spreadsheets})
            if method == "POST":
                body = self._body()
                name = (body.get("name") or "").strip()
                if not name:
                    return self._send(400, {"error": "name_required"})
                sid = "sp_" + uuid4hex(10)
                spreadsheets.append({"spreadsheet_id": sid, "name": name,
                                     "worksheets": []})
                self.store.write("sheets.json", sheets)
                self.store.audit({"op": "sheets:create-spreadsheet", "name": name})
                return self._send(201, {"spreadsheet_id": sid, "name": name})
            return self._send(405, {"error": "method_not_allowed"})
        sid = parts[0]
        sp = next((x for x in spreadsheets if x.get("spreadsheet_id") == sid), None)
        if len(parts) == 1:
            if method == "GET":
                if sp is None:
                    return self._send(404, {"error": "no_such_spreadsheet"})
                return self._send(200, {"spreadsheet_id": sid, "name": sp.get("name"),
                                        "exists": True,
                                        "worksheets": sp.get("worksheets", [])})
            return self._send(405, {"error": "method_not_allowed"})
        if len(parts) == 2 and parts[1] == "sheets":
            if sp is None:
                return self._notfound("no_such_spreadsheet")
            if method == "POST":
                body = self._body()
                title = (body.get("title") or "").strip()
                if not title:
                    return self._send(400, {"error": "title_required"})
                wid = "ws_" + uuid4hex(8)
                sp.setdefault("worksheets", []).append({"sheet_id": wid, "title": title})
                self.store.write("sheets.json", sheets)
                self.store.audit({"op": "sheets:create-worksheet", "spreadsheet": sid})
                return self._send(201, {"sheet_id": wid, "title": title,
                                        "spreadsheet_id": sid})
            return self._send(405, {"error": "method_not_allowed"})
        if len(parts) == 3 and parts[1] == "sheets":
            wid = parts[2]
            if sp is None:
                return self._send(404, {"error": "no_such_spreadsheet"})
            ws = next((w for w in sp.get("worksheets", []) if w.get("sheet_id") == wid), None)
            if method == "GET":
                return self._send(200, {"spreadsheet_id": sid, "sheet_id": wid,
                                        "exists": ws is not None,
                                        "title": ws.get("title") if ws else None})
        return self._notfound()

    # -------------------------------------------------------------- identity
    def _identity(self, method, rest):
        data = self.store.read("identity.json", {"accounts": []})
        accounts = data.setdefault("accounts", [])
        parts = [p for p in rest.split("/") if p]
        if len(parts) == 1 and parts[0] == "accounts":
            if method == "GET":
                return self._send(200, {"accounts": accounts})
            return self._send(405, {"error": "method_not_allowed"})
        if len(parts) == 2 and parts[0] == "accounts":
            uid = parts[1]
            if method == "GET":
                acc = next((a for a in accounts if a.get("user_id") == uid), None)
                if acc is None:
                    return self._send(404, {"error": "no_such_account"})
                return self._send(200, acc)
            if method == "DELETE":
                found = [a for a in accounts if a.get("user_id") == uid]
                if not found:
                    return self._send(404, {"error": "no_such_account"})
                accounts[:] = [a for a in accounts if a.get("user_id") != uid]
                self.store.write("identity.json", data)
                self.store.audit({"op": "identity:delete", "user": uid})
                return self._send(200, {"deleted": True, "user_id": uid,
                                        "remaining": len(accounts)})
            return self._send(405, {"error": "method_not_allowed"})
        return self._notfound()

    # ------------------------------------------------------------------ http
    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def do_PUT(self):
        self._route("PUT")

    def do_DELETE(self):
        self._route("DELETE")


def uuid4hex(n):
    import uuid
    return uuid.uuid4().hex[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", default="/app/store")
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    Handler.store = Store(args.store)
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print("cloudsvc listening on %s:%d store=%s" % (args.host, args.port, args.store), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()