#!/usr/bin/env bash
# Merkstock verifier (executes-deliverable).
# Executes every deliverable on hidden inputs in /tests/hidden and end-to-end
# against the live service, then writes the reward to /logs/verifier/reward.txt.
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
import base64
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

HALL = "/tests/hidden"
FAIL = []


def fail(m):
    FAIL.append(m)


def read_json(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


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
            pb = resp.read()
            try:
                return resp.status, (json.loads(pb.decode()), resp.headers.get("Content-Type"))
            except Exception:
                return resp.status, (pb.decode(), resp.headers.get("Content-Type"))
    except urllib.error.HTTPError as e:
        pb = e.read().decode()
        try:
            j = (json.loads(pb), e.headers.get("Content-Type"))
        except Exception:
            j = (pb, e.headers.get("Content-Type"))
        return e.code, j


try:
    ready = False
    for _ in range(80):
        try:
            st, _ = http("GET", "/api/v1/health")
            if st == 200:
                ready = True
                break
        except Exception:
            time.sleep(0.3)
    if not ready:
        fail("API server never became ready")
    else:
        st, (body, _) = http("GET", "/api/v1/health")
        if not (st == 200 and isinstance(body, dict) and body.get("status") == "ok"):
            fail("health -> %s %s" % (st, body))

        # ---------------- hidden: query-parameter 400 matrix ----------------
        for c in read_json(os.path.join(HALL, "param_1", "cases.json")):
            st, (body, _) = http(c["method"] if "method" in c else "GET", c["path"])
            if st != c["expect"]:
                fail("blocks%s -> %d, want %d" % (c["path"], st, c["expect"]))
                continue
            if c.get("code"):
                if not (isinstance(body, dict) and body.get("error", {}).get("code") == c["code"]):
                    fail("blocks%s code: got %s, want %s" % (c["path"], body, c["code"]))
            elif st != 200 and not (isinstance(body, dict) and body.get("error")):
                fail("blocks%s status %d lacked an error envelope" % (c["path"], st))

        # ---------------- hidden: not-found identifier lookups --------------
        for c in read_json(os.path.join(HALL, "lookup_1", "cases.json")):
            st, (body, _) = http(c["method"], c["path"])
            if st != c["expect"]:
                fail("%s %s -> %d, want %d" % (c["method"], c["path"], st, c["expect"]))
                continue
            if c["expect"] == 404:
                # structured not-found: exactly one top-level field "error"
                if not isinstance(body, dict) or set(body.keys()) != {"error"}:
                    fail("%s not-found body not single-error-field: %r" % (c["path"], body))
                elif body["error"].get("code") != "not_found":
                    fail("%s not-found code wrong: %r" % (c["path"], body))
            elif c["expect"] == 200 and not isinstance(body, dict):
                fail("%s expected JSON object, got %r" % (c["path"], body))

        # ---------------- hidden: traversal upload neutralization -----------
        for c in read_json(os.path.join(HALL, "upload_1", "cases.json")):
            st, (body, _) = http("POST", "/api/v1/uploads", c)
            if st != c["expect"]:
                fail("upload %s -> %d, want %d (%r)" % (c["name"], st, c["expect"], body))
                continue
            if c["expect"] == 201:
                if not (isinstance(body, dict) and body.get("stored") == c["name"]):
                    fail("upload %s stored=%r, want safe basename %r" % (c["name"], body.get("stored"), c["name"]))
                if body.get("size") != len(base64.b64decode(c["data"], validate=True)):
                    fail("upload %s size mismatch: %r" % (c["name"], body))

        # traversal must never have escaped /app/uploads
        for esc in ("/app/escape.txt", "/app/passwd", "/app/etc", "/app/Windows"):
            if os.path.exists(esc):
                fail("path traversal escaped to %s" % esc)

        # service still reachable + functional after the traversal attempts
        st, (body, _) = http("GET", "/api/v1/health")
        if not (st == 200 and body.get("status") == "ok"):
            fail("health after traversal attempts -> %s %r" % (st, body))
        st, (body, _) = http("POST", "/api/v1/uploads",
                             {"name": "post_traversal.txt", "data": "YQ==", "tokens": 1})
        if st != 201:
            fail("legit upload after traversal -> %d, service not functional" % st)

        # ---------------- hidden: comment render 400/404 -------------------
        for c in read_json(os.path.join(HALL, "render_1", "cases.json")):
            st, (body, _) = http("GET", c["path"])
            if st != c["expect"]:
                fail("%s -> %d, want %d" % (c["path"], st, c["expect"]))
                continue
            if not (isinstance(body, dict) and body.get("error", {}).get("code") == c["code"]):
                fail("%s body %r, want code %s" % (c["path"], body, c["code"]))

        # success path + sanitizer interposition on renders
        plain_body = "<p>plain note</p>"
        st, n = http("POST", "/api/v1/comments", {"title": "hello", "body": plain_body})
        if st != 201:
            fail("comment create -> %d" % st)
        else:
            cid = n[0]["id"]
            st, (body, ctype) = http("GET", "/api/v1/comments/%d/render" % cid)
            if st != 200 or plain_body not in (body or ""):
                fail("render plain comment -> %d" % st)
            elif ctype and "text/html" not in ctype:
                fail("render content-type not text/html: %r" % ctype)
            if body and body != (( '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"></head>'
                                  '<body>%s</body></html>') % sanitizer.sanitize(plain_body)):
                fail("render body deviates from sanitize-envelope of supplied body")
        # --- deliver the stored-XSS proof via the live render endpoint ---
        xss = open("/app/xss.html", encoding="utf-8").read()
        st, nb = http("POST", "/api/v1/comments", {"title": "xss", "body": xss})
        if st != 201:
            fail("xss comment create -> %d" % st)
        else:
            xid = nb[0]["id"]
            st, (served, ctype) = http("GET", "/api/v1/comments/%d/render" % xid)
            if st != 200:
                fail("xss render -> %d" % st)
            else:
                if served is None or sanitizer.sanitize(xss) not in served:
                    fail("render output does not contain sanitizer.sanitize(xss.html)")
                if "<script" in (served or "").lower():
                    fail("render still contained a <script tag")
                from playwright.sync_api import sync_playwright
                msgs = []
                with sync_playwright() as pw:
                    b = pw.chromium.launch()
                    pg = b.new_page()
                    pg.on("dialog", lambda d: (msgs.append(d.message), d.accept())[1])
                    pg.set_content(served, timeout=10000)
                    pg.wait_for_timeout(400)
                    b.close()
                if not any("AMBERORCHID" in m for m in msgs):
                    fail("headless chromium: no AMBERORCHID alert (%r)" % msgs)

        # ---------------- contract doc + security report -----------------------
        st, (doc, _) = http("GET", "/api/v1/doc.json")
        file_sc = read_json("/app/schema.json")
        if st != 200:
            fail("/api/v1/doc.json -> %d" % st)
        elif doc != file_sc:
            fail("/api/v1/doc.json does not mirror /app/schema.json")
        need_paths = ["/api/v1/health", "/api/v1/blocks", "/api/v1/blocks/{hash}",
                      "/api/v1/txs/{txid}", "/api/v1/uploads", "/api/v1/comments",
                      "/api/v1/comments/{id}/render", "/api/v1/doc.json"]
        if not (isinstance(file_sc, dict)):
            fail("schema.json not an object")
        else:
            pths = file_sc.get("paths", {})
            missing = [p for p in need_paths if p not in pths]
            if missing:
                fail("schema paths missing: %s" % missing)
            report = file_sc.get("security", {}).get("report", [])
            hit = [r for r in report if isinstance(r, dict) and r.get("cwe") == "CWE-22"
                   and "helpers.py" in str(r.get("file", ""))]
            if not hit:
                fail("security.report missing CWE-22 reference to helpers.py: %r" % report)
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

print("ALL PASS -- Merkstock OK")
open("/logs/verifier/reward.txt", "w").write("1")
PYEOF
exit 0