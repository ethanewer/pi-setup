#!/usr/bin/env python3
"""Verifier logic for zephyr-vault (executes-deliverable).

Executes every deliverable with literal /app paths and validates behavior:
  - /app/app.py is launched on 127.0.0.1:5001; /identity keeps the Flask
    framework/version banner; every SSTI/code-exec payload class (visible battery
    in instruction + hidden batteries under /tests/hidden) is neutralized
    (computed token absent from a 200 response); malformed render inputs -> 200;
  - /app/server_check.py runs and reports pass=True (independently re-verified);
  - /app/sheets_client.py is run (idempotent), then /app/sheets_result.json is
    cross-checked against the spreadsheet REST mock (resources exist, nested,
    linked), edge names are created, and malformed requests reject cleanly.
  - /app/audit_report.md flags the string-concatenation SQL injection.

Exits 0 iff everything passes. Writes no reward file; test.sh does.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

from importlib import metadata as _md

FLASK_MAJOR = _md.version("flask").split(".")[0]

APP_PORT = 5001
APP_BASE = "http://127.0.0.1:%d" % APP_PORT
SVC_PORT = 5002
SVC_BASE = "http://127.0.0.1:%d" % SVC_PORT
HIDDEN = "/tests/hidden"

APP = "/app/app.py"
SERVER_CHECK = "/app/server_check.py"
SERVER_REPORT = "/app/server_report.json"
CLIENT = "/app/sheets_client.py"
RESULT = "/app/sheets_result.json"
AUDIT = "/app/audit_report.md"

BASE_PAYLOADS = [
    ("{{ 7*7 }}", "49"),
    ("<%= 9*9 %>", "81"),
    ("`x-${6*6}`", "36"),
    ("<?php echo 4*4; ?>", "16"),
    ("{% set n = 5*5 %}{{ n }}", "25"),
    ("<# 8*8 #>", "64"),
    ('<!--#exec cmd="id" -->', "NEVER_EVAL_GHOST"),
]
MALFORMED = [
    {"name": None},
    {"name": ["list", {"nested": 3}]},
    {"name": 12345},
]

failures = []


def http(method, url, body=None, timeout=5):
    req = urllib.request.Request(url, method=method)
    payload = None
    if isinstance(body, dict):
        payload = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, payload, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, str(e)


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("  FAIL:", msg)


def start_app():
    subprocess.run(["pkill", "-f", "app.py"], check=False)
    time.sleep(0.3)
    subprocess.Popen([sys.executable, APP], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + 15
    while time.time() < deadline:
        st, _ = http("GET", APP_BASE + "/identity")
        if st == 200:
            return True
        time.sleep(0.25)
    return False


def stop_app():
    subprocess.run(["pkill", "-f", "app.py"], check=False)


def audit_check():
    print("[audit]")
    if not os.path.exists(AUDIT):
        check(False, "audit_report.md missing")
        return
    text = open(AUDIT, encoding="utf-8", errors="replace").read()
    need = ["SQL injection", "concatenat", "auth_service.py", "find_user", "parameter"]
    for n in need:
        check(n.lower() in text.lower(), "audit missing mention: %r" % n)


def server_probe():
    print("[server probe]")
    if not os.path.exists(APP):
        check(False, "app.py missing")
        return
    if not start_app():
        check(False, "app.py server failed to start")
        return
    try:
        inst_major = FLASK_MAJOR
        idents = []
        for _ in range(3):
            st, body = http("GET", APP_BASE + "/identity")
            d = json.loads(body) if st == 200 else {}
            idents.append(d)
            check(st == 200 and d.get("app") == "AuroraVault"
                  and d.get("framework") == "Flask",
                  "identity banner incorrect on probe (st=%s)" % st)
        good = [d for d in idents if d.get("flask_major") == inst_major]
        check(len(good) == 3, "flask_major not stable/equal to installed %s" % inst_major)

        all_payloads = list(BASE_PAYLOADS)
        if os.path.isdir(HIDDEN):
            for fn in sorted(os.listdir(HIDDEN)):
                if fn.startswith("fuzz_payloads_"):
                    data = json.load(open(os.path.join(HIDDEN, fn)))
                    for p in data.get("payloads", []):
                        all_payloads.append((p["name"], p["absent"]))

        for payload, absent in all_payloads:
            st, body = http("POST", APP_BASE + "/render", {"name": payload})
            check(st == 200, "render returned %s for %r" % (st, payload[:40]))
            check(absent not in body, "payload evaluated (token %r leaked) for %r"
                  % (absent, payload[:40]))

        for m in MALFORMED:
            st, _ = http("POST", APP_BASE + "/render", m)
            check(st == 200, "malformed render returned %s for %r" % (st, m))
    finally:
        stop_app()


def server_check_deliverable():
    print("[server_check.py]")
    if not os.path.exists(SERVER_CHECK):
        check(False, "server_check.py missing")
        return
    r = subprocess.run([sys.executable, SERVER_CHECK], capture_output=True, text=True)
    check(r.returncode == 0, "server_check.py exited %d" % r.returncode)
    if os.path.exists(SERVER_REPORT):
        rep = json.load(open(SERVER_REPORT))
        for key in ("framework_ok", "all_neutralized", "malformed_handled", "pass"):
            check(bool(rep.get(key)), "server_report.json %s != true" % key)
    else:
        check(False, "server_report.json not produced")


def ensure_service():
    st, _ = http("GET", SVC_BASE + "/health")
    if st != 200:
        subprocess.Popen([sys.executable, "/app/src/sheets_service.py"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        deadline = time.time() + 15
        while time.time() < deadline:
            st, _ = http("GET", SVC_BASE + "/health")
            if st == 200:
                break
            time.sleep(0.25)
        check(st == 200, "spreadsheet service did not start")


def run_client(args):
    r = subprocess.run([sys.executable, CLIENT] + args, capture_output=True, text=True)
    return r


def get_spreadsheet(sid):
    st, body = http("GET", SVC_BASE + "/spreadsheets/" + sid)
    if st == 200:
        return json.loads(body)
    return None


def get_sheet(sid, wsid):
    st, body = http("GET", SVC_BASE + "/spreadsheets/%s/sheets/%s" % (sid, wsid))
    if st == 200:
        return json.loads(body)
    return None


def sheets_check():
    print("[sheets]")
    if not os.path.exists(CLIENT):
        check(False, "sheets_client.py missing")
        return
    ensure_service()

    r = run_client([])
    check(r.returncode == 0, "sheets_client.py default exited %d: %s" % (r.returncode, r.stderr[-300:]))
    if not os.path.exists(RESULT):
        check(False, "sheets_result.json not produced")
        return
    res = json.load(open(RESULT))
    sid, wsid = res.get("spreadsheet_id"), res.get("sheet_id")
    check(sid and wsid, "sheets_result.json missing ids")
    if not (sid and wsid):
        return
    spr = get_spreadsheet(sid)
    check(spr is not None and spr.get("name") == "ZephyrOps Ledger",
          "spreadsheet %s not found by name" % sid)
    sheets = spr.get("sheets", []) if spr else []
    check(any(sh.get("id") == wsid and sh.get("name") == "Ledger A" for sh in sheets),
          "worksheet %s not nested in spreadsheet" % wsid)
    sht = get_sheet(sid, wsid)
    check(sht is not None and sht.get("spreadsheet_id") == sid and sht.get("name") == "Ledger A",
          "worksheet link invalid")

    # idempotency: second run must not create duplicates / change the id
    before = http("GET", SVC_BASE + "/spreadsheets")[1]
    before = json.loads(before)["spreadsheets"]
    r = run_client([])
    check(r.returncode == 0, "sheets_client.py re-run failed")
    after = json.loads(http("GET", SVC_BASE + "/spreadsheets")[1])["spreadsheets"]
    check(len(after) == len(before), "spreadsheet store grew on re-run (not idempotent)")

    # edge creates (unicode/special characters) driven through the deliverable
    edge = {"name": "Budget \u03942024", "sheet": "Revenue \u03a3"}
    if os.path.isdir(HIDDEN):
        ep = os.path.join(HIDDEN, "spreadsheet_edges.json")
        if os.path.exists(ep):
            edge = json.load(open(ep))
    r = run_client(["--name", edge["name"], "--sheet", edge["sheet"]])
    check(r.returncode == 0, "sheets_client.py edge exited %d: %s" % (r.returncode, r.stderr[-300:]))
    res2 = json.load(open(RESULT))
    sid2, wsid2 = res2.get("spreadsheet_id"), res2.get("sheet_id")
    spr2 = get_spreadsheet(sid2) if sid2 else None
    check(spr2 is not None and spr2.get("name") == edge["name"],
          "edge spreadsheet %r not created" % edge["name"])
    check(any(sh.get("id") == wsid2 and sh.get("name") == edge["sheet"] for sh in (spr2 or {}).get("sheets", [])),
          "edge worksheet not nested")
    sht2 = get_sheet(sid2, wsid2) if (sid2 and wsid2) else None
    check(sht2 is not None and sht2.get("spreadsheet_id") == sid2, "edge worksheet link invalid")

    # malformed creates reject cleanly
    malformed = {"name": ""}
    if os.path.isdir(HIDDEN):
        mp = os.path.join(HIDDEN, "malformed_spreadsheets.json")
        if os.path.exists(mp):
            for c in json.load(open(mp))["cases"]:
                st, body = http(c["http_method"], SVC_BASE + c["path"], c.get("body"))
                check(st == c["expect_http"], "malformed %s %s -> %s (want %s)"
                      % (c["http_method"], c["path"], st, c["expect_http"]))
    r = run_client(["--name", ""])
    check(r.returncode != 0, "sheets_client.py should fail cleanly on empty name")
    check(("error" in (r.stderr + r.stdout).lower()), "client gave no error on empty name")


def main():
    audit_check()
    server_probe()
    server_check_deliverable()
    sheets_check()
    if failures:
        print("\n%d failure(s)" % len(failures))
        return 1
    print("\nALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())