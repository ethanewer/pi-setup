#!/bin/bash
# Verifier for keelson-berth (executes-deliverable).
#
# The agent must author, from scratch, a Java 21 + Maven HTTP catalogue
# service at /app/service (JDK com.sun.net.httpserver, hand-rolled
# constructor injection, SQLite via JDBC, hand-rolled JSON, JUnit 5 tests)
# plus an /app/run_server.sh launcher.  The verifier:
#   1. requires both deliverables to exist,
#   2. requires a JUnit 5 test class somewhere under src/test,
#   3. runs `mvn -q -B -o verify` against the pre-seeded offline Maven repo,
#   4. starts the packaged service through the launcher against three hidden
#      SQLite fixture databases (different data, different sizes, including
#      an empty store) and drives the whole HTTP contract over real sockets,
#      deriving every expectation from the fixture's own rows.
# Reward is strictly 0 or 1; this trap guarantees a reward on every path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -f /app/service/pom.xml ]; then
  echo "FAIL: deliverable /app/service/pom.xml missing (no Maven project authored)"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/run_server.sh ]; then
  echo "FAIL: deliverable /app/run_server.sh missing"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

OUT=$(python3 - <<'PY'
import glob
import http.client
import json
import os
import sqlite3
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from urllib.parse import quote

SERVICE = "/app/service"
LAUNCHER = "/app/run_server.sh"
M2 = "-Dmaven.repo.local=/opt/m2repo"

FAILURES = []


def fail(msg):
    FAILURES.append(msg)
    print("FAIL:", msg)


def req(port, method, path, headers=None, body=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        c.request(method, path, body=body, headers=headers or {})
        r = c.getresponse()
        data = r.read()
        hdrs = {k.lower(): v for k, v in r.getheaders()}
        return r.status, hdrs, data
    finally:
        c.close()


def jload(b):
    try:
        return json.loads(b)
    except Exception:
        return None


def as_num(v):
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        return float(v)
    return None


def item_equal(a, b):
    if not isinstance(a, dict) or not isinstance(b, dict):
        return False
    if set(a.keys()) != set(b.keys()):
        return False
    for k in a:
        av, bv = a[k], b[k]
        if k == "price":
            pa, pb = as_num(av), as_num(bv)
            if pa is None or pb is None or abs(pa - pb) > 1e-9:
                return False
        else:
            if av != bv:
                return False
    return True


def items_equal(expected, actual):
    if not isinstance(actual, list) or len(expected) != len(actual):
        return False
    return all(item_equal(a, b) for a, b in zip(expected, actual))


def rows_to_items(rows):
    return [{"sku": s, "title": t, "price": float(p), "quantity": int(q),
             "category": c} for s, t, p, q, c in rows]


def read_rows(dbpath):
    con = sqlite3.connect(dbpath)
    try:
        con.isolation_level = None
        return con.execute(
            "SELECT sku, title, price, quantity, category"
            " FROM items ORDER BY sku").fetchall()
    finally:
        con.close()


def make_db(case_dir, dbpath):
    seed = os.path.join(case_dir, "seed.sql")
    con = sqlite3.connect(dbpath)
    try:
        con.executescript(open(seed, encoding="utf-8").read())
    finally:
        con.close()


def stop_server():
    pidfile = "/app/server.pid"
    if os.path.exists(pidfile):
        try:
            os.kill(int(open(pidfile).read().strip()), 15)
        except Exception:
            pass
        try:
            os.remove(pidfile)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# 0. deliverable sanity
# ---------------------------------------------------------------------------
if not os.path.exists(SERVICE):
    fail("no services under " + SERVICE)
    sys.exit(1)
if not os.path.exists(LAUNCHER):
    fail("launcher missing")
    sys.exit(1)

tests = [
    p for p in glob.glob(SERVICE + "/src/test/**/*.java", recursive=True)
    if os.path.isfile(p)
]
if not tests:
    fail("no test sources under /app/service/src/test; the project must ship "
         "a JUnit 5 suite")
    sys.exit(1)
if not any("@Test" in open(p, encoding="utf-8", errors="replace").read()
           for p in tests):
    fail("no @Test methods found in /app/service/src/test")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 1. the shipped tests must compile and pass, fully offline
# ---------------------------------------------------------------------------
print("running: mvn -q -B -o verify")
try:
    r = subprocess.run(
        ["mvn", "-q", "-B", "-o", M2, "verify"],
        cwd=SERVICE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=540)
except subprocess.TimeoutExpired:
    fail("mvn verify timed out after 540s")
    sys.exit(1)
except FileNotFoundError:
    fail("mvn not found")
    sys.exit(1)
if r.returncode != 0:
    tail = r.stdout.decode(errors="replace")[-3000:]
    fail("mvn -q -B -o verify failed (project does not build or its own "
         "JUnit suite is red)")
    print(tail)
    sys.exit(1)

# -- the shipped JUnit 5 suite must have genuinely run and passed during
#    that verify.  A file under src/test that merely contains the text
#    "@Test" (say, in a comment) or a battery of empty-bodied tests passes
#    the substring check above while executing nothing meaningful, and such
#    a project still green-lights `mvn verify`.  Parse the surefire reports:
#    at least 5 tests must have executed across the whole project, with zero
#    failures and zero errors.
reports = sorted(glob.glob(SERVICE + "/target/surefire-reports/TEST-*.xml"))
executed = 0
failures = 0
errors = 0
for rep in reports:
    try:
        root = ET.parse(rep).getroot()
    except Exception:
        continue
    executed += int(root.get("tests") or 0)
    failures += int(root.get("failures") or 0)
    errors += int(root.get("errors") or 0)
if executed < 5 or failures or errors:
    fail("the shipped JUnit suite did not actually execute and pass: "
         "%d executed, %d failures, %d errors across %d surefire reports; "
         "the contract requires a real suite (JSON codec tests, service "
         "tests over an injected fake repository, and an end-to-end HTTP "
         "test) that runs green under `mvn -q -B -o verify`"
         % (executed, failures, errors, len(reports)))
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2. hidden fixtures: start the service through the launcher and drive the
#    whole contract; expectations are derived from each fixture's own rows.
# ---------------------------------------------------------------------------
hidden = sorted(p for p in os.listdir("/tests/hidden")
                if os.path.isdir(os.path.join("/tests/hidden", p)))
if not hidden:
    fail("no hidden cases under /tests/hidden")
    sys.exit(1)

port_base = 18100

for idx, name in enumerate(hidden):
    case_dir = os.path.join("/tests/hidden", name)
    tag = "kb-" + name.lower()
    port = port_base + idx
    dbpath = "/tmp/kb-" + name + ".sqlite"

    if os.path.exists(dbpath):
        try:
            os.remove(dbpath)
        except OSError:
            pass
    try:
        make_db(case_dir, dbpath)
    except Exception as e:
        fail("%s: could not build fixture db: %r" % (name, e))
        continue

    expected = rows_to_items(read_rows(dbpath))
    categories = sorted({it["category"] for it in expected})
    filter_cat = categories[0] if categories else None

    stop_server()
    try:
        r = subprocess.run(
            ["bash", LAUNCHER, dbpath, str(port)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    except subprocess.TimeoutExpired:
        fail("%s: /app/run_server.sh hung (server run in foreground?)" % name)
        continue
    except Exception as e:
        fail("%s: /app/run_server.sh failed to run: %r" % (name, e))
        continue
    if r.returncode != 0:
        fail("%s: /app/run_server.sh exited %d: %s"
             % (name, r.returncode, r.stdout.decode(errors="replace")[-500:]))
        continue

    # -- readiness: poll GET /healthz ---------------------------------
    ready = False
    for _ in range(120):
        try:
            st, h, b = req(port, "GET", "/healthz")
            if st == 200 and jload(b) == {"ok": True}:
                ready = True
                break
        except Exception:
            pass
        time.sleep(0.5)
    if not ready:
        fail("%s: service never answered /healthz within 60s" % name)
        if os.path.exists("/app/server.out.log"):
            print("  server.out.log:", " | ".join(
                open("/app/server.out.log", errors="replace").read()
                .splitlines()[-6:])[-400:])
        stop_server()
        continue

    ct_ok = [True]

    def check_ct(h, where):
        ct = h.get("content-type", "")
        if not ct.startswith("application/json"):
            ct_ok[0] = False
            fail("%s: %s response Content-Type is %r, want application/json"
                 % (name, where, ct))

    # -- GET all -------------------------------------------------------
    st, h, b = req(port, "GET", "/api/v1/items")
    if st != 200:
        fail("%s: GET /api/v1/items returned %d" % (name, st))
    else:
        check_ct(h, "list")
        body = jload(b)
        if not isinstance(body, dict) or body.get("count") != len(expected):
            fail("%s: list count %r != %d" % (name, body.get("count") if isinstance(body, dict) else b[:80], len(expected)))
        elif not items_equal(expected, body.get("items")):
            fail("%s: list items do not match fixture rows (order + values)" % name)

    # -- GET filter (existing category, empty category, garbage) --------
    filter_checks = []
    if filter_cat is not None:
        filter_checks.append(
            (filter_cat, [it for it in expected if it["category"] == filter_cat]))
    filter_checks.append(("zzz-no-such-%s" % tag, []))
    for cat, want in filter_checks:
        st, h, b = req(port, "GET", "/api/v1/items?category=" + cat)
        if st != 200:
            fail("%s: GET category=%s returned %d" % (name, cat, st))
        else:
            body = jload(b)
            if not isinstance(body, dict) or body.get("count") != len(want):
                fail("%s: filter %s count %r != %d"
                     % (name, cat, body.get("count") if isinstance(body, dict) else b[:80], len(want)))
            elif not items_equal(want, body.get("items")):
                fail("%s: filter %s items wrong" % (name, cat))

    # -- GET single -----------------------------------------------------
    if expected:
        first, second = expected[0], expected[1]
        st, h, b = req(port, "GET", "/api/v1/items/" + quote(first["sku"], safe=""))
        if st != 200 or not item_equal(first, jload(b).get("item") if isinstance(jload(b), dict) else None):
            fail("%s: GET single %s returned %d %r" % (name, first["sku"], st, b[:120]))
    st, h, b = req(port, "GET", "/api/v1/items/never-here-%s" % tag)
    if st != 404 or jload(b) != {"error": "not_found"}:
        fail("%s: GET missing sku returned %d %r" % (name, st, b[:120]))

    # -- POST valid -> 201, then visible in list/filter -----------------
    posted_sku = "new-%s-01" % tag
    posted = {"sku": posted_sku, "title": "Fresh stock item",
              "price": 3.75, "quantity": 4, "category": filter_cat or "default"}
    st, h, b = req(port, "POST", "/api/v1/items",
                   {"Content-Type": "application/json"}, json.dumps(posted))
    if st != 201:
        fail("%s: POST returned %d %r" % (name, st, b[:160]))
    else:
        body = jload(b)
        if not isinstance(body, dict) or not item_equal(posted, body.get("item")):
            fail("%s: POST response body %r != posted item" % (name, b[:160]))

    # the write must persist to the fixture file
    refreshed = rows_to_items(read_rows(dbpath))
    if not any(it["sku"] == posted_sku for it in refreshed):
        fail("%s: POST did not persist to the SQLite file" % name)
    else:
        st, h, b = req(port, "GET", "/api/v1/items")
        body = jload(b)
        if not isinstance(body, dict) or body.get("count") != len(refreshed) \
                or not items_equal(refreshed, body.get("items")):
            fail("%s: GET after POST does not reflect the new row" % name)
        if filter_cat:
            st, h, b = req(port, "GET", "/api/v1/items?category=" + filter_cat)
            body = jload(b)
            want = [it for it in refreshed if it["category"] == filter_cat]
            if not isinstance(body, dict) or body.get("count") != len(want) \
                    or not items_equal(want, body.get("items")):
                fail("%s: filter after POST does not include the new row" % name)

    # -- POST duplicate, bad json, invalid item -------------------------
    if expected:
        st, h, b = req(port, "POST", "/api/v1/items",
                       {"Content-Type": "application/json"},
                       json.dumps({"sku": expected[0]["sku"], "title": "X",
                                   "price": 1, "quantity": 1,
                                   "category": "x"}))
        if st != 409 or jload(b) != {"error": "duplicate_sku"}:
            fail("%s: duplicate POST returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "POST", "/api/v1/items",
                   {"Content-Type": "application/json"},
                   '{"sku": "x"')
    if st != 400 or jload(b) != {"error": "bad_json"}:
        fail("%s: malformed body returned %d %r" % (name, st, b[:120]))
    for bad in (
            {"sku": "y", "title": "", "price": 1, "quantity": 1, "category": "c"},
            {"sku": "y", "title": "t", "price": -1, "quantity": 1, "category": "c"},
            {"sku": "y", "title": "t", "price": 1, "quantity": 2.5, "category": "c"},
            {"sku": "y", "title": "t", "price": "1", "quantity": 1, "category": "c"},
            {"sku": "y", "title": "t", "price": 1, "quantity": 1}):
        st, h, b = req(port, "POST", "/api/v1/items",
                       {"Content-Type": "application/json"}, json.dumps(bad))
        if st != 400 or jload(b) != {"error": "invalid_item"}:
            fail("%s: invalid item %r returned %d %r" % (name, bad, st, b[:120]))

    # -- method / path errors -------------------------------------------
    st, h, b = req(port, "PUT", "/api/v1/items",
                   {"Content-Type": "application/json"}, json.dumps(posted))
    if st != 405 or jload(b) != {"error": "method_not_allowed"}:
        fail("%s: PUT /api/v1/items returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "GET", "/api/v1/" + tag + "-nope")
    if st != 404 or jload(b) != {"error": "not_found"}:
        fail("%s: unknown /api path returned %d %r" % (name, st, b[:120]))

    # -- DELETE ----------------------------------------------------------
    if expected:
        victim = expected[0]["sku"]
        st, h, b = req(port, "DELETE", "/api/v1/items/" + quote(victim, safe=""))
        if st != 200 or jload(b) != {"deleted": True}:
            fail("%s: DELETE %s returned %d %r" % (name, victim, st, b[:120]))
        st, h, b = req(port, "GET", "/api/v1/items/" + victim)
        if st != 404:
            fail("%s: GET after DELETE returned %d" % (name, st))
        st, h, b = req(port, "DELETE", "/api/v1/items/" + quote(victim, safe=""))
        if st != 404:
            fail("%s: second DELETE returned %d, want 404" % (name, st))
    st, h, b = req(port, "DELETE", "/api/v1/items/absent-%s" % tag)
    if st != 404:
        fail("%s: DELETE of absent row returned %d" % (name, st))

    stop_server()
    time.sleep(0.3)
    try:
        os.remove(dbpath)
    except OSError:
        pass

if FAILURES:
    print("\n%d failure(s) across %d hidden case(s)"
          % (len(FAILURES), len(hidden)))
    sys.exit(1)
print("ALL PASS: mvn verify green; %d hidden case(s): list/filter/get/post/"
      "duplicate/delete/errors verified against fixture-derived expectations"
      % len(hidden))
sys.exit(0)
PY
)
RC=$?
printf '%s\n' "$OUT"

if [ "$RC" = "0" ]; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
exit 0