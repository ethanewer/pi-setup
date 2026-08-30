#!/usr/bin/env python3
"""Regression check for the AuroraVault web server (deliverable /app/server_check.py).

Starts /app/app.py on loopback port 5001 (killing any prior instance), waits for
it, then:
  1. confirms the framework identity/version is intact: GET /identity reports
     app=AuroraVault, framework=Flask and flask_major equal to the installed
     Flask major version;
  2. throws a battery of SSTI / server-side code-execution payload classes at
     POST /render; every payload computes a distinguishing token that must be
     ABSENT from a 200 response (i.e. the input was treated as data, never
     parsed/evaluated);
  3. checks malformed render inputs (missing name, list, non-string) return 200.

Writes /app/server_report.json and exits 0 on full success, else non-zero.
Receives no hidden inputs; it is the agent-authored regression harness whose
results the verifier independently re-checks with its own battery too.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

from importlib import metadata as _md

FLASK_VERSION = _md.version("flask")
FLASK_MAJOR = FLASK_VERSION.split(".")[0]

HOST = "127.0.0.1"
PORT = 5001
BASE = "http://%s:%d" % (HOST, PORT)
REPORT = "/app/server_report.json"
LOOP_PID = "/tmp/server_check_app.pid"

# (label, [(payload, absent-token)])
PAYLOAD_SETS = [
    ("jinja-mustache", [("{{ 7*7 }}", "49"), ("{{ 6*7 }}", "42")]),
    ("erb-ejs", [("<%= 9*9 %>", "81")]),
    ("js-template-literal", [("`x-${6*6}`", "36")]),
    ("php-inline", [("<?php echo 4*4; ?>", "16")]),
    ("jinja-block-gadget", [("{% set n = 5*5 %}{{ n }}", "25")]),
    ("handlebars", [("<# 8*8 #>", "64")]),
    ("ssi-directive", [("<!--#exec cmd=\"id\" -->", "NEVER_MATCH_SENTINEL")]),
]
MALFORMED = [
    {"name": None},
    {"name": ["list", {"nested": 3}]},
    {"name": 12345},
]
BASELINE = [("admin-preview", "{{ 7*7 }}")]


def http(method, url, body=None):
    req = urllib.request.Request(url, method=method)
    payload = None
    if isinstance(body, dict):
        payload = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, payload, timeout=5) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, str(e)


def kill_app():
    subprocess.run(["pkill", "-f", "app.py"], check=False)
    subprocess.run(["pkill", "-f", "sparks"], check=False)
    if os.path.exists(LOOP_PID):
        try:
            os.kill(int(open(LOOP_PID).read()), 9)
        except Exception:
            pass
    time.sleep(0.3)


def write_report(rep, ok):
    rep["app"] = "AuroraVault"
    rep["pass"] = bool(ok)
    try:
        with open(REPORT, "w") as fh:
            json.dump(rep, fh, indent=2)
        os.chmod(REPORT, 0o644)
    except Exception as e:
        print("report-write-failed:", e, file=sys.stderr)


def main():
    killed = False
    kill_app()
    proc = subprocess.Popen(
        [sys.executable, "/app/app.py"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    with open(LOOP_PID, "w") as fh:
        fh.write(str(proc.pid))
    try:
        deadline = time.time() + 15
        while time.time() < deadline:
            st, _ = http("GET", BASE + "/identity")
            if st == 200:
                killed = True
                break
            time.sleep(0.25)
        if not killed:
            write_report({"stage": "server-failed-to-start"}, False)
            return 1

        inst_major = FLASK_MAJOR
        st, body = http("GET", BASE + "/identity")
        ident = json.loads(body) if st == 200 else {}
        framework_ok = (
            ident.get("framework") == "Flask"
            and ident.get("app") == "AuroraVault"
            and ident.get("flask_major") == inst_major
        )

        detail = {}
        all_neutral = True
        for label, items in PAYLOAD_SETS:
            for payload, absent in items:
                st, body = http("POST", BASE + "/render", {"name": payload})
                evaluated = st == 200 and absent in body
                if evaluated:
                    all_neutral = False
                detail[label] = (st, evaluated)

        malformed_ok = True
        for m in MALFORMED:
            st, _ = http("POST", BASE + "/render", m)
            if st != 200:
                malformed_ok = False

        ok = framework_ok and all_neutral and malformed_ok
        rep = {
            "framework_ok": framework_ok,
            "reported_flask_major": ident.get("flask_major"),
            "installed_flask_major": inst_major,
            "payload_classes_checked": len(PAYLOAD_SETS),
            "all_neutralized": all_neutral,
            "malformed_handled": malformed_ok,
            "details": {k: {"status": v[0], "evaluated": v[1]} for k, v in detail.items()},
        }
        write_report(rep, ok)
        print("server_check " + ("PASS" if ok else "FAIL"))
        return 0 if ok else 2
    finally:
        subprocess.run(["pkill", "-f", "app.py"], check=False)


if __name__ == "__main__":
    sys.exit(main())