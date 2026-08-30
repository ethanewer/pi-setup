#!/usr/bin/env bash
# Gale Vault verifier (executes-deliverable).
# Invokes every deliverable, including on hidden inputs in /tests/hidden, then
# writes REWARD to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

for f in /app/api.py /app/schema.json /app/xss.html; do
  if [ ! -s "$f" ]; then
    echo "missing deliverable $f" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
  fi
done

python3 - <<'PYEOF'
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, "/app")
import sanitizer

FAIL = []


def fail(m):
    FAIL.append(m)


HALL = "/tests/hidden"


def read_json(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


# ------------------------------------------------------------------
# 1. Load the hardened canonicalizer and check hidden header matrix.
#    (C-1d626fbd) reject control chars / blanks by raising; keep canonical
#    title forms for benign names.
# ------------------------------------------------------------------
import importlib.util
_spec = importlib.util.spec_from_file_location("galeapi", "/app/api.py")
api = importlib.util.module_from_spec(_spec)
sys.modules["galeapi"] = api
_spec.loader.exec_module(api)

for case in read_json(os.path.join(HALL, "headers_1", "cases.json")):
    name = case["name"]
    if case["expect"] == "error":
        try:
            api.canonical_header(name)
            fail("canonical_header(%r) should raise, returned value" % name)
        except ValueError:
            pass
    else:
        try:
            got = api.canonical_header(name)
        except ValueError as e:
            fail("canonical_header(%r) raised for a benign name: %s" % (name, e))
            continue
        if got != case["expect"]:
            fail("canonical_header(%r)=%r want %r" % (name, got, case["expect"]))

# ---------------------------------------------------------------------------
# 2. Start the live API and drive it with hidden upload + query cases.
# ---------------------------------------------------------------------------
PORT = 8039
server = subprocess.Popen(["python3", "/app/api.py", str(PORT)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
BASE = "http://127.0.0.1:%d" % PORT


def http(meth, path, body=None):
    if body is not None:
        data = json.dumps(body).encode()
    else:
        data = None
    req = urllib.request.Request(BASE + path, data=data, method=meth,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=6) as resp:
            payload = resp.read()
            try:
                return resp.status, json.loads(payload.decode())
            except Exception:
                return resp.status, payload.decode()
    except urllib.error.HTTPError as e:
        try:
            p = json.loads(e.read().decode())
        except Exception:
            p = None
        return e.code, p


ready = False
try:
    for _ in range(60):
        try:
            http("GET", "/api/v1/doc.json")
            ready = True
            break
        except Exception:
            time.sleep(0.3)
    if not ready:
        fail("API server never became ready")

    if ready:
        # --- upload hidden cases (the live REST upload endpoint) ---
        up = read_json(os.path.join(HALL, "upload_1", "post.json"))
        st, body = http("POST", "/api/v1/notes", up["valid"])
        if st != 201:
            fail("valid upload -> %d, want 201 (%s)" % (st, body))
        else:
            valid_id = body["id"]
            st, det = http("GET", "/api/v1/notes/%d" % valid_id)
            if st != 200:
                fail("detail of uploaded note -> %d, want 200" % st)
            elif list(det.get("headers", {}).keys()) != up["valid_expect_header_names"]:
                fail("stored headers not canonicalized: %r"
                     % list(det.get("headers", {}).keys()))

        st2, body2 = http("POST", "/api/v1/notes",
                          {"title": "beta", "body": "b2", "tags": []})
        if st2 != 201:
            fail("beta upload -> %d, want 201" % st2)

        # poisoned header (control char) MUST be a 400; nothing stored
        st, body = http("POST", "/api/v1/notes", up["poisoned"])
        if st != 400 or not (isinstance(body, dict) and body.get("error")):
            fail("poisoned header -> %d, want structured 400 (%s)" % (st, body))

        st, _ = http("POST", "/api/v1/notes", up["missing_title"])
        if st != 400:
            fail("missing title -> %d, want 400" % st)
        st, _ = http("POST", "/api/v1/notes", up["bad_body"])
        if st != 400:
            fail("non-string body -> %d, want 400" % st)

        # --- headless-browser XSS end-to-end via the live render endpoint ---
        xss_raw = open("/app/xss.html", encoding="utf-8").read()
        st, nb = http("POST", "/api/v1/notes",
                      {"title": "xss", "body": xss_raw, "tags": []})
        if st != 201:
            fail("xss upload -> %d, want 201" % st)
        else:
            xid = nb["id"]
            st, rendered = http("GET", "/api/v1/notes/%d/render" % xid)
            served = rendered if isinstance(rendered, str) else ""
            if st != 200:
                fail("render of xss note -> %d, want 200" % st)
            else:
                if served != sanitizer.sanitize(xss_raw):
                    fail("render output != sanitizer.sanitize(xss.html)")
                if "<script" in served.lower():
                    fail("render still contained a <script tag")
                # headless Chromium must auto-fire an alert (no interaction)
                from playwright.sync_api import sync_playwright
                msg = []
                with sync_playwright() as pw:
                    b = pw.chromium.launch()
                    pg = b.new_page()
                    pg.on("dialog", lambda d: (msg.append(d.message), d.accept())[1])
                    pg.set_content(served, timeout=10000)
                    pg.wait_for_timeout(300)
                    b.close()
                if not any("GALEVAULT" in m for m in msg):
                    fail("headless chromium: no GALEVAULT alert (%r)" % msg)

        # --- query / path parameter hidden cases ---
        for c in read_json(os.path.join(HALL, "params_1", "cases.json")):
            st, body = http(c["method"], c["path"])
            if st != c["expect"]:
                fail("%s %s -> %d, want %d" % (c["method"], c["path"], st, c["expect"]))
                continue
            if c.get("code") and not (isinstance(body, dict) and
                                      body.get("error", {}).get("code") == c["code"]):
                fail("%s %s missing code %s in body %s"
                     % (c["method"], c["path"], c["code"], body))

        # --- contract doc: served schema == delivered schema.json; CWEs mapped
        st, doc = http("GET", "/api/v1/doc.json")
        file_sc = read_json("/app/schema.json")
        if st != 200:
            fail("/api/v1/doc.json -> %d, want 200" % st)
        elif doc != file_sc:
            fail("/api/v1/doc.json does not mirror /app/schema.json")
        if not (isinstance(file_sc, dict) and
                "/api/v1/notes" in file_sc.get("paths", {}) and
                "/api/v1/notes/{id}" in file_sc.get("paths", {}) and
                "/api/v1/notes/{id}/render" in file_sc.get("paths", {})):
            fail("schema doc missing required contract routes")
        vuln = file_sc.get("security", {}).get("vulnerabilities", [])
        cwes = {v.get("cwe") for v in vuln if isinstance(v, dict)}
        if not ({"CWE-79", "CWE-113"} <= cwes):
            fail("schema.doc vulnerabilities missing CWE-79/CWE-113: %s" % cwes)
finally:
    server.terminate()
    try:
        server.wait(timeout=6)
    except Exception:
        server.kill()

if FAIL:
    print("FAILURES (%d):" % len(FAIL))
    for m in FAIL:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS — Gale Vault OK")
open("/logs/verifier/reward.txt", "w").write("1")
PYEOF
exit 0