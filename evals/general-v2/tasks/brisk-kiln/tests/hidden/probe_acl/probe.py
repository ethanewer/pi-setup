#!/usr/bin/env python3
"""Hidden probe 1 (brisk-kiln): list content, closed/open posting
enforcement, subscribe semantics, unknown-list 404s. Exits 0 on success."""
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8418"

SPEC = {
    "hostname": "lists.grebe-lake.net",
    "lists": [
        {"name": "announce", "owner": "ops@grebe-lake.net", "closed": True,
         "members": ["ops@grebe-lake.net", "warden@grebe-lake.net"]},
        {"name": "alerts", "owner": "ops@grebe-lake.net", "closed": True,
         "members": ["ops@grebe-lake.net"]},
        {"name": "chatter", "owner": "rosa@grebe-lake.net", "closed": False,
         "members": ["rosa@grebe-lake.net", "finn@example.org"]},
    ],
}


def req(method, path, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method)
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        try:
            return resp.code, resp.read().decode("utf-8")
        except Exception:
            return resp.code, ""
    except Exception:
        return 0, ""


def die(label, detail):
    print("probe_acl FAIL: %s (%s)" % (label, detail), file=sys.stderr)
    sys.exit(1)


def check(cond, label, detail=""):
    if not cond:
        die(label, detail)


def norm_lists(payload):
    obj = json.loads(payload)
    assert isinstance(obj, dict) and "lists" in obj
    lists = sorted(obj["lists"], key=lambda l: l["name"])
    norm = []
    for lst in obj["lists"]:
        assert set(lst) >= {"name", "owner", "closed", "members"}, lst
        norm.append({"name": lst["name"], "owner": lst["owner"],
                     "closed": bool(lst["closed"]),
                     "members": sorted(lst["members"])})
    want = []
    for lst in SPEC:
        want.append({"name": lst["name"], "owner": lst["owner"],
                     "closed": lst["closed"], "members": sorted(lst["members"])})
    want.sort(key=lambda l: l["name"])
    return obj.get("hostname"), want, sorted([l["name"] for l in obj["lists"]])


def main():
    code, body = req("GET", "/health")
    check(code == 200, "health status", "%s %s" % (code, body[:200]))
    try:
        h = json.loads(body)
    except Exception:
        check(False, "health json", body[:200])
        return
    check(h.get("status") == "ok", "health status", body[:200])
    check(h.get("config") == "/etc/listd/lists.conf", "health config path",
          body[:200])
    check(h.get("hostname") == "lists.grebe-lake.net", "health hostname",
          body[:200])

    code, body = req("GET", "/lists")
    check(code == 200, "lists status", "%s %s" % (code, body[:200]))
    try:
        hostname, want = norm_lists(body)
    except Exception as exc:
        check(False, "lists parse", "%s: %r" % (exc, body[:200]))
        return
    check(hostname == SPEC["hostname"], "lists hostname", str(hostname))
    check(want == SPEC_WANT, "lists content", body[:400])

    # posting on the closed lists
    code, body = req("POST", "/post", {
        "list": "announce", "from": "ops@grebe-lake.net",
        "subject": "Weekly status", "body": "All systems nominal at the lake."})
    check(code == 200, "announce member post", "%s %s" % (code, body[:200]))
    code, body = req("POST", "/post", {
        "list": "announce", "from": "finn@example.org",
        "subject": "intrusion", "body": "should be rejected"})
    check(code == 403, "announce non-member post", str(code))
    code, body = req("POST", "/post", {
        "list": "alerts", "from": "warden@grebe-lake.net",
        "subject": "page", "body": "x"})
    check(code == 403, "alerts non-member post", str(code))
    # open list: anyone may post
    code, body = req("POST", "/post", {
        "list": "chatter", "from": "outsider@example.net",
        "subject": "hello from outside", "body": "just passing by"})
    check(code == 200, "chatter open post", "%s %s" % (code, body[:200]))
    # subscribe semantics
    code, body = req("POST", "/subscribe",
                     {"list": "chatter", "address": "nova@grebe-lake.net"})
    check(code == 200, "open subscribe", "%s %s" % (code, body[:200]))
    code, body = req("GET", "/lists")
    check(code == 200, "lists after subscribe", str(code))
    try:
        lists = {l["name"]: l for l in json.loads(body)["lists"]}
    except Exception:
        check(False, "lists parse after subscribe", body[:200])
        return
    check("nova@grebe-lake.net" in lists["chatter"]["members"],
          "subscribe reflected", body[:400])
    for closed_list in ("announce", "alerts"):
        code, body = req("POST", "/subscribe",
                         {"list": closed_list,
                          "address": "nova@grebe-lake.net"})
        check(code == 403, "closed subscribe refused (%s)" % closed_list,
              str(code))
    code, _ = req("POST", "/subscribe", {"list": "ghost-list",
                                         "address": "x@y.z"})
    check(code == 404, "unknown list subscribe", str(code))
    code, _ = req("POST", "/post", {"list": "ghost-list", "from": "x@y.z",
                                    "subject": "s", "body": "b"})
    check(code == 404, "unknown list post", str(code))
    print("probe_acl ok", file=sys.stderr)
    sys.exit(0)
