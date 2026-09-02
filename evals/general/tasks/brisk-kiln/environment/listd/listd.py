#!/usr/bin/env python3
#
# listd.py -- a small mailing-list manager daemon (Grebe Lake infrastructure).
#
# Reads exactly one configuration file at startup (the canonical path below)
# and serves an HTTP API on 127.0.0.1:<port from [global]>.
#
# Exit code 2 with a stderr diagnostic if the configuration is missing,
# unreadable, malformed, or violates the schema. In that state the daemon
# never starts and the lists do not function.
import configparser
import json
import os
import re
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CANONICAL_CONFIG = "/etc/listd/lists.conf"
LIST_RE = re.compile(r"[a-z0-9_-]{1,64}$")


def fail(msg):
    sys.stderr.write("listd: %s\n" % msg)
    sys.exit(2)


def load_config(path):
    if not os.path.isfile(path):
        fail("configuration not found: %s" % path)
    cp = configparser.ConfigParser()
    try:
        cp.read(path, encoding="utf-8")
    except configparser.Error as exc:
        fail("configuration parse error: %s" % exc)
    if not cp.has_section("global"):
        fail("missing [global] section")
    for key in ("hostname", "spool", "port"):
        if not cp.has_option("global", key):
            fail("missing [global].%s" % key)
    try:
        port = int(str(cp.get("global", "port")).strip())
    except ValueError:
        fail("[global].port must be an integer")
    if not (1 <= port <= 65535):
        fail("[global].port out of range")
    hostname = str(cp.get("global", "hostname")).strip()
    spool = str(cp.get("global", "spool")).strip()
    if not spool:
        fail("[global].spool must be a path")

    lists = {}
    for sec in cp.sections():
        if sec == "global":
            continue
        if not sec.startswith("list."):
            fail("unknown section [%s]" % sec)
        name = sec[len("list."):]
        if not LIST_RE.match(name):
            fail("bad list name: %r" % name)
        for key in ("owner", "closed"):
            if not cp.has_option(sec, key):
                fail("[%s] missing key %r" % (sec, key))
        closed = str(cp.get(sec, "closed")).strip().lower()
        if closed not in ("true", "yes", "on", "1", "false", "no", "off", "0"):
            fail("[%s] closed must be true/false" % sec)
        owner = str(cp.get(sec, "owner")).strip()
        members_raw = str(cp.get(sec, "members", fallback="")).strip()
        members = [m.strip() for m in members_raw.split(",") if m.strip()]
        lists[name] = {
            "name": name,
            "owner": owner,
            "closed": closed in ("true", "yes", "on", "1"),
            "members": members,
        }
    if not lists:
        fail("no list sections")
    return {"hostname": hostname, "spool": spool, "port": port, "lists": lists}



def main():
    cfg = load_config(CANONICAL_CONFIG)
    os.makedirs(cfg["spool"], exist_ok=True)
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "listd/1.0"

        def _send_json(self, code, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_raw(self, code, raw, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/health":
                self._send_json(200, {"status": "ok",
                                      "config": CANONICAL_CONFIG,
                                      "hostname": cfg["hostname"],
                                      "port": cfg["port"]})
                return
            if path == "/lists":
                listing = []
                for name in sorted(cfg["lists"]):
                    lst = cfg["lists"][name]
                    listing.append({
                        "name": name,
                        "owner": lst["owner"],
                        "closed": lst["closed"],
                        "members": list(lst["members"]),
                    })
                self._send_json(200, {"hostname": cfg["hostname"],
                                      "lists": listing})
                return
            m = re.fullmatch(r"/archive/([a-z0-9_-]{1,64})", path)
            if m:
                name = m.group(1)
                if name not in cfg["lists"]:
                    self._send_json(404, {"error": "unknown list"})
                    return
                fpath = os.path.join(cfg["spool"], name + ".mbox")
                if not os.path.isfile(fpath):
                    self._send_json(404, {"error": "no archive yet"})
                    return
                with open(fpath, "r", encoding="utf-8") as fh:
                    self._send_raw(200, fh.read().encode("utf-8"), "text/plain")
                return
            self._send_json(404, {"error": "not found"})

        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length") or 0)
                payload = json.loads(self.rfile.read(length) or b"{}")
                if not isinstance(payload, dict):
                    raise ValueError("not an object")
            except Exception:
                self._send_json(400, {"error": "bad JSON body"})
                return
            path = urllib.parse.urlsplit(self.path).path
            if path == "/subscribe":
                name = str(payload.get("list") or "")
                addr = str(payload.get("address") or "")
                with lock:
                    lst = cfg["lists"].get(name)
                    if lst is None:
                        self._send_json(404, {"error": "unknown list"})
                        return
                    if lst["closed"]:
                        self._send_json(403, {"error": "list is closed"})
                        return
                    if addr and addr not in lst["members"]:
                        lst["members"] = list(lst["members"]) + [addr]
                    self._send_json(200, {"ok": True, "list": name,
                                          "members": list(lst["members"])})
                return
            if path == "/post":
                name = str(payload.get("list") or "")
                sender = str(payload.get("from") or "")
                subject = str(payload.get("subject") or "")
                body = str(payload.get("body") or "")
                with lock:
                    lst = cfg["lists"].get(name)
                    if lst is None:
                        self._send_json(404, {"error": "unknown list"})
                        return
                    allowed = (not lst["closed"]) or (sender in lst["members"])
                    if not allowed:
                        self._send_json(403, {"error": "sender not a member"})
                        return
                    ts = time.strftime("%a %b %d %H:%M:%S %Y")
                    mbox_msg = ("From %s %s\n" % (sender, ts)
                                + "From: %s\n" % sender
                                + "To: %s@%s\n" % (name, cfg["hostname"])
                                + "Subject: %s\n" % subject
                                + "\n"
                                + body + "\n\n")
                    with open(os.path.join(cfg["spool"], name + ".mbox"),
                              "a", encoding="utf-8") as fh:
                        fh.write(mbox_msg)
                self._send_json(200, {"ok": True, "list": name,
                                      "delivered": True})
                return
            self._send_json(404, {"error": "unknown endpoint"})

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(),
                                            fmt % args))

    server = ThreadingHTTPServer(("127.0.0.1", cfg["port"]), Handler)
    server.daemon_threads = True
    sys.stderr.write("listd: serving on 127.0.0.1:%d with config %s\n"
                     % (cfg["port"], CANONICAL_CONFIG))
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
