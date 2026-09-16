#!/bin/bash
# Verifier for culvert-keel (executes-deliverable).
# Starts the agent's Go service through the deliverable launcher against each
# hidden config fixture (H1/H2/H3, different keys, principals, limits and
# data), drives the HTTP contract with real requests (happy path, 401, 429
# under a measured burst, request-ID echo, per-principal isolation, refill
# recovery, registry state), then audits the structured JSON log. Reward is
# strictly 0 or 1.
#
# Guarantee a reward on every exit path. Without this a verifier that raises
# while inspecting the agent's deliverable writes nothing at all, which
# yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if [ ! -f /app/run_server.sh ]; then
  echo "FAIL: deliverable /app/run_server.sh missing"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/server/main.go ]; then
  echo "FAIL: /app/server/main.go missing (service source not delivered)"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

OUT=$(python3 - <<'PY' 2>&1
import http.client
import json
import os
import shutil
import subprocess
import sys
import time

FAILURES = []


def fail(msg):
    FAILURES.append(msg)
    print("FAIL:", msg)


def jload(b):
    try:
        return json.loads(b)
    except Exception:
        return None


def req(port, method, path, headers=None, body=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        c.request(method, path, body=body, headers=headers or {})
        r = c.getresponse()
        data = r.read()
        hdrs = {k.lower(): v for k, v in r.getheaders()}
        return r.status, hdrs, data
    finally:
        c.close()


hidden = sorted(
    p for p in os.listdir("/tests/hidden")
    if os.path.isdir(os.path.join("/tests/hidden", p))
)
if not hidden:
    fail("no hidden cases under /tests/hidden")

port_base = 18100
case_logs = []

for idx, name in enumerate(hidden):
    case = "/tests/hidden/" + name
    tag = "ck-" + name.lower()
    with open(case + "/server.json") as f:
        cfg = json.load(f)
    cap = int(cfg["rate_limit"]["capacity"])
    refill = float(cfg["rate_limit"]["refill_per_sec"])
    tokens = []
    with open(case + "/keys.txt") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#") or "=" not in ln:
                continue
            t, p = ln.split("=", 1)
            tokens.append((t.strip(), p.strip()))
    if len(tokens) < 4:
        fail("%s: fixture needs at least 4 tokens" % name)
        continue
    with open(case + "/entries.json") as f:
        entries = json.load(f)["entries"]

    pa_tok, pa = tokens[0]
    pb_tok, pb = tokens[1]
    pc_tok, pc = tokens[2]
    pd_tok, pd = tokens[3]
    port = port_base + idx

    # fresh log + no stale server
    open("/app/server.log", "w").close()
    if os.path.exists("/app/server.pid"):
        try:
            os.kill(int(open("/app/server.pid").read().strip()), 15)
        except Exception:
            pass
    try:
        r = subprocess.run(
            ["bash", "/app/run_server.sh", case, str(port)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        fail("%s: /app/run_server.sh hung (server foreground?)" % name)
        continue
    except Exception as e:
        fail("%s: /app/run_server.sh failed to run: %r" % (name, e))
        continue
    if r.returncode != 0:
        fail("%s: /app/run_server.sh exited %d: %s"
             % (name, r.returncode, r.stdout.decode(errors="replace")[-400:]))
        continue

    # readiness poll: GET /healthz must answer
    ready = False
    for _ in range(60):
        try:
            st, h, b = req(port, "GET", "/healthz")
            if st == 200:
                ready = True
                if jload(b) != {"ok": True}:
                    fail("%s: /healthz body not {\"ok\":true}: %r" % (name, b))
                break
        except Exception:
            pass
        time.sleep(0.5)
    if not ready:
        fail("%s: server not ready on /healthz within 30s" % name)
        if os.path.exists("/app/server.out.log"):
            tail = open("/app/server.out.log").read()[-500:]
            print("  server.out.log:", tail.replace("\n", " | ")[-400:])
        continue

    # --- request-ID echo (client-supplied ID must propagate to the response) --
    rid1 = tag + "-echo"
    st, h, b = req(port, "GET", "/api/v1/registry",
                   {"Authorization": "Bearer " + pa_tok, "X-Request-ID": rid1})
    if st != 200:
        fail("%s: authed GET returned %d" % (name, st))
    else:
        got = jload(b)
        if h.get("x-request-id") != rid1:
            fail("%s: X-Request-ID %r not echoed (got %r)"
                 % (name, rid1, h.get("x-request-id")))
        if got is None or got.get("principal") != pa:
            fail("%s: principal in GET body wrong" % name)
        elif got.get("entries") != entries:
            fail("%s: entries on GET do not match fixture" % name)

    # --- generated request IDs (absent header -> fresh UUID per request) ----
    ids = set()
    for _ in range(2):
        st, h, b = req(port, "GET", "/api/v1/registry",
                       {"Authorization": "Bearer " + pa_tok})
        rid = h.get("x-request-id")
        if not rid:
            fail("%s: missing generated X-Request-ID" % name)
        else:
            ids.add(rid)
    if len(ids) != 2:
        fail("%s: generated request IDs are not fresh per request" % name)

    # --- 401 paths: missing, unknown, and non-Bearer credentials --------------
    for hdrs in ({}, {"Authorization": "Bearer nope-" + tag},
                 {"Authorization": "Basic " + "b3Jz9ZTk="}):
        st, h, b = req(port, "GET", "/api/v1/registry", hdrs)
        if st != 401 or jload(b) != {"error": "unauthorized"}:
            fail("%s: expected 401 unauthorized for headers %r, got %d"
                 % (name, hdrs, st))
        if "bearer" not in h.get("www-authenticate", "").lower():
            fail("%s: 401 missing WWW-Authenticate: Bearer" % name)

    # --- registry mutation (statefulness): POST -> GET, 409, 400, 405, 404 ---
    added = {"name": "pendulum-%d" % idx, "value": "v" + name}
    body = json.dumps(added)
    st, h, b = req(port, "POST", "/api/v1/registry",
                   {"Authorization": "Bearer " + pb_tok,
                    "Content-Type": "application/json"}, body)
    if st != 201 or jload(b) != {"added": added, "principal": pb}:
        fail("%s: POST add returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "POST", "/api/v1/registry",
                   {"Authorization": "Bearer " + pb_tok}, body)
    if st != 409 or jload(b) != {"error": "duplicate_name"}:
        fail("%s: duplicate POST returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "GET", "/api/v1/registry",
                   {"Authorization": "Bearer " + pb_tok})
    if st != 200:
        fail("%s: GET after POST returned %d" % (name, st))
    elif jload(b).get("entries") != entries + [added]:
        fail("%s: GET after POST does not reflect the added row" % name)
    st, h, b = req(port, "POST", "/api/v1/registry",
                   {"Authorization": "Bearer " + pb_tok}, "not json {")
    if st != 400 or jload(b) != {"error": "bad_json"}:
        fail("%s: bad JSON POST returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "PUT", "/api/v1/registry",
                   {"Authorization": "Bearer " + pc_tok}, body)
    if st != 405 or jload(b) != {"error": "method_not_allowed"}:
        fail("%s: PUT returned %d %r" % (name, st, b[:120]))
    st, h, b = req(port, "GET", "/api/v1/" + name.lower() + "-missing",
                   {"Authorization": "Bearer " + pc_tok})
    if st != 404 or jload(b) != {"error": "not_found"}:
        fail("%s: unknown /api path returned %d %r" % (name, st, b[:120]))

    # --- measured burst: cap+2 requests, must trip 429 with Retry-After -------
    resp = []
    for _ in range(cap + 2):
        st, h, b = req(port, "GET", "/api/v1/registry",
                       {"Authorization": "Bearer " + pd_tok})
        resp.append((st, h, b))
    codes = [x[0] for x in resp]
    n429 = sum(1 for c in codes if c == 429)
    if n429 == 0:
        fail("%s: burst of %d produced no 429 (codes=%s)"
             % (name, cap + 2, codes))
    else:
        st, h, b = next(x for x in resp if x[0] == 429)
        if "retry-after" not in h:
            fail("%s: 429 missing Retry-After header" % name)
        if jload(b) != {"error": "rate_limited"}:
            fail("%s: 429 body wrong: %r" % (name, b[:120]))

        # per-principal isolation: while pd is exhausted, pc must stay green
        st, h, b = req(port, "GET", "/api/v1/registry",
                       {"Authorization": "Bearer " + pc_tok})
        if st != 200:
            fail("%s: throttling leaked to an unthrottled principal (%d)"
                 % (name, st))
        # an unknown token during exhaustion must still be 401, never 429
        st, h, b = req(port, "GET", "/api/v1/registry",
                       {"Authorization": "Bearer unknown-" + tag})
        if st != 401:
            fail("%s: unknown token during burst got %d, want 401" % (name, st))

        # refill recovery: bucket must refill, not hard-block
        # Sleep generously so the gate keeps >=3x margin even at the fastest host
        # (worst case leaves exactly 1 token available; no flake in the bad direction).
        time.sleep(3.0 / refill + 2.0)
        st, h, b = req(port, "GET", "/api/v1/registry",
                       {"Authorization": "Bearer " + pd_tok})
        if st != 200:
            fail("%s: throttled principal did not recover after refill (%d)"
                 % (name, st))

    # --- capture this case's log for the audit below ---
    try:
        shutil.copyfile("/app/server.log", "/tmp/cklog-" + name + ".log")
    except OSError:
        pass
    case_logs.append(name)

    # --- stop the server ---
    if os.path.exists("/app/server.pid"):
        try:
            os.kill(int(open("/app/server.pid").read().strip()), 15)
        except Exception:
            pass
    time.sleep(0.2)

# ---------------------------------------------------------------------------
# structured JSON log audit (per case)
# ---------------------------------------------------------------------------
REQKEYS = {"ts", "request_id", "method", "path", "status", "principal"}
for name in case_logs:
    path = "/tmp/cklog-" + name + ".log"
    if not os.path.exists(path):
        fail("%s: no log file produced at configured log_file" % name)
        continue
    lines = open(path).read().splitlines()
    if not lines:
        fail("%s: log file is empty" % name)
        continue
    seen_401 = seen_429 = False
    for ln in lines:
        obj = jload(ln)
        if not isinstance(obj, dict):
            fail("%s: log line is not a JSON object: %r" % (name, ln[:100]))
            continue
        if not REQKEYS.issubset(set(obj.keys())):
            fail("%s: log line missing required keys: %r" % (name, sorted(obj.keys())))
            continue
        if not isinstance(obj.get("ts"), int) or not isinstance(obj.get("status"), int):
            fail("%s: log line ts/status not int" % name)
        if not isinstance(obj.get("request_id"), str) or not obj.get("request_id"):
            fail("%s: log line empty request_id" % name)
        if obj.get("status") == 401:
            seen_401 = True
        if obj.get("status") == 429:
            seen_429 = True
    if not seen_401:
        fail("%s: no log record with status 401" % name)
    if not seen_429:
        fail("%s: no log record with status 429" % name)
    # the echoed request ID must be correlated to its request in the log
    rid1 = "ck-" + name.lower() + "-echo"
    if not any(
        obj.get("request_id") == rid1 and obj.get("status") == 200
        and obj.get("path") == "/api/v1/registry"
        for obj in (jload(ln) for ln in lines)
        if isinstance(jload(ln), dict)
    ):
        fail("%s: log has no record correlating echoed request id %s with 200"
             % (name, rid1))

if FAILURES:
    print("\n%d failure(s) across %d hidden case(s)" % (len(FAILURES), len(hidden)))
    sys.exit(1)
print("ALL PASS: %d hidden case(s), contract + log audit clean" % len(hidden))
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