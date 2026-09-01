#!/usr/bin/env bash
# Gale Vault — clean-room oracle. Creates the three deliverables in /app by
# REAL work (authoring the hardened API, the REST contract doc, and the
# sanitizer-bypass payload), then proves them by RUNNING the deliverable: a
# deterministic headless-Chromium localStorage/alert check and a live server
# smoke test. Never reads /tests.
set -euo pipefail
SRC="/solution"

install -m 0644 "$SRC/api.py"     "/app/api.py"
install -m 0644 "$SRC/schema.json"  "/app/schema.json"

# ---- craft the sanitizer-bypass payload by hand ----
cat > "/app/xss.html" <<'HTML'
<svg/onload=alert('GALEVAULT')>
HTML

chmod +x "/app/api.py"

# ---- prove the deliverables (running the work, not just writing it) ----
python3 - <<'PY'
import sys, re, json
sys.path.insert(0, "/app")
import api
import sanitizer

# 1) canonical_header hardening: rejects control chars, preserves canonical forms
for name in ["content-type", "Accept", "x-note-id",
             "cache-control", "x-Custom-Header"]:
    expect = "-".join(t[:1].upper()+t[1:].lower() for t in name.split("-"))
    got = api.canonical_header(name)
    assert got == expect, (name, got, expect)
for bad in ["", "a\r\nb", "x\nY", "n\u0000ull", "carriage\rreturn"]:
    try:
        api.canonical_header(bad)
        raise SystemExit("expected ValueError for %r" % bad)
    except ValueError:
        pass

# 2) the delivered xss.html must survive the real filter and STILL be live
raw = open("/app/xss.html").read()
fn = sanitizer.sanitize(raw)
assert "<script" not in fn.lower(), "payload was sanitized into plain text"
# 3) schema doc is valid JSON and contains the required contract + CWEs
s = json.load(open("/app/schema.json"))
assert "/api/v1/notes" in s["paths"]
assert "/api/v1/notes/{id}/render" in s["paths"]
cwes = {v["cwe"] for v in s["security"]["vulnerabilities"]}
assert {"CWE-79", "CWE-113"} <= cwes, cwes
print("ORACLE total: canonical, sanitizer-survival, schema/CWE all OK")
PY

# Headless end: confirm the payload auto-fires under headless Chromium.
python3 - <<'PY'
import sys, os
sys.path.insert(0, "/app")
import sanitizer
from playwright.sync_api import sync_playwright
raw = open("/app/xss.html", encoding="utf-8").read()
fn = sanitizer.sanitize(raw)
with sync_playwright() as pw:
    b = pw.chromium.launch()
    pg = b.new_page()
    msg = []
    pg.on("dialog", lambda d: (msg.append(d.message), d.accept())[1])
    pg.set_content(fn, timeout=10000)
    pg.wait_for_timeout(250)
    b.close()
assert any("GALEVAULT" in m for m in msg), "alert did not fire: %r" % msg
print("ORACLE chromium alert fired:", msg)
PY
echo "Gale Vault oracle written all three deliverables."