#!/bin/bash
# Verifier for quartz-haven (executes-deliverable).
# Drives the deliverable /app/api.py (imported as a WSGI app and once as a
# live server) on the visible case and on every hidden case, enforcing
# per-case wall-clock limits, then writes REWARD to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

for f in /app/api.py /app/summary.json; do
  if [ ! -s "$f" ]; then
    echo "missing deliverable $f" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
  fi
done

python3 - <<'PYEOF'
import importlib.util
import io
import json
import os
import subprocess
import sys
import time
import urllib.request

FAIL = []


def fail(m):
    FAIL.append(m)
    print("FAIL:", m)


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as e:
        fail("unreadable JSON %s: %s" % (path, e))
        return None


# The deliverable module must import cleanly WITHOUT starting a server.
try:
    import signal

    def _alarm(signum, frame):
        raise TimeoutError("import timed out (server started on import?)")

    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(20)
    spec = importlib.util.spec_from_file_location("qh_api", "/app/api.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    signal.alarm(0)
except Exception as e:
    print("fatal: cannot import /app/api.py: %s" % e)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

if not hasattr(mod, "application"):
    fail("/app/api.py does not expose WSGI callable 'application'")

_counter = [0]


def fresh_mod():
    """Reload the deliverable module so every case starts from empty state."""
    _counter[0] += 1
    spec = importlib.util.spec_from_file_location(
        "qh_api_%d" % _counter[0], "/app/api.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def call(method, path, body=None):
    mod = fresh_mod()
    raw = json.dumps(body).encode() if body is not None else b""
    env = {
        "REQUEST_METHOD": method, "PATH_INFO": path, "QUERY_STRING": "",
        "SERVER_NAME": "127.0.0.1", "SERVER_PORT": "80",
        "SERVER_PROTOCOL": "HTTP/1.1", "CONTENT_LENGTH": str(len(raw)),
        "CONTENT_TYPE": "application/json",
        "wsgi.version": (1, 0), "wsgi.url_scheme": "http",
        "wsgi.input": io.BytesIO(raw), "wsgi.errors": io.StringIO(),
        "wsgi.multithread": False, "wsgi.multiprocess": False,
        "wsgi.run_once": False,
    }
    out = {}
    chunks = mod.application(env, lambda s, h, e=None: out.update(s=s))
    data = b"".join(chunks)
    code = int(out["s"].split()[0])
    try:
        parsed = json.loads(data.decode("utf-8"))
    except Exception:
        parsed = None
    return code, parsed


def close_enough(got, want, tol=0.01):
    if isinstance(want, bool) or isinstance(got, bool):
        return got is want
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        return abs(float(got) - float(want)) <= tol
    if isinstance(want, dict) and isinstance(got, dict):
        return set(want) == set(got) and all(close_enough(got[k], want[k], tol)
                                             for k in want)
    if isinstance(want, list) and isinstance(got, list):
        return len(want) == len(got) and all(close_enough(g, w, tol)
                                             for g, w in zip(got, want))
    return got == want


def check_lookups(expected):
    for aid, want in expected["lookups"].items():
        code, got = call("GET", "/api/v1/assets/%s" % aid)
        if want["status"] == 404:
            if code != 404:
                fail("lookup %s -> %d, want 404" % (aid, code))
        else:
            if code != 200 or not close_enough(got, want["asset"]):
                fail("lookup %s -> %d %r, want %r" % (aid, code, got,
                                                      want["asset"]))


def check_summary(expected, label):
    code, got = call("GET", "/api/v1/portfolio/summary")
    if code != 200:
        fail("%s summary -> %d" % (label, code))
        return
    if not close_enough(got, expected["summary"]):
        fail("%s summary mismatch: got %r want %r"
             % (label, got, expected["summary"]))


def run_hidden_case(cdir):
    case = read_json(os.path.join(cdir, "case.json"))
    exp = read_json(os.path.join(cdir, "expected.json"))
    if case is None or exp is None:
        return
    t0 = time.monotonic()
    for i, batch in enumerate(case["bulk"]):
        code, got = call("POST", "/api/v1/assets/bulk", {"assets": batch})
        want = exp["batches"][i]
        if code != want["status"]:
            fail("bulk batch %d -> %d, want %d" % (i, code, want["status"]))
        elif not close_enough(got, {"accepted": want["accepted"],
                                    "total": want["total"]}):
            fail("bulk batch %d body %r, want %r" % (i, got, want))
    for i, batch in enumerate(case["invalid_batches"]):
        code, got = call("POST", "/api/v1/assets/bulk", {"assets": batch})
        want = exp["invalid_batches"][i]
        if code != want["status"]:
            fail("invalid batch %d -> %d, want %d" % (i, code, want["status"]))
        elif code == 400 and not (isinstance(got, dict) and
                                  got.get("error", {}).get("code") ==
                                  "bad_request"):
            fail("invalid batch %d missing structured error: %r" % (i, got))
    check_lookups(exp)
    check_summary(exp, "case %s" % os.path.basename(cdir))
    elapsed = time.monotonic() - t0
    limit = case.get("time_limit_sec", 60)
    if elapsed > limit:
        fail("case %s took %.1fs (limit %.0fs) — does not scale"
             % (os.path.basename(cdir), elapsed, limit))
    else:
        print("case %s ok in %.1fs" % (os.path.basename(cdir), elapsed))


HALL = "/tests/hidden"
try:
    # ---- visible case: ingest the shipped fixture, check summary ----
    vis = read_json("/app/visible_portfolio.json")
    vexp = read_json("/tests/expected.json")
    if vis and vexp:
        code, got = call("POST", "/api/v1/assets/bulk", vis)
        if code != 201 or got.get("accepted") != len(vis["assets"]):
            fail("visible bulk -> %d %r" % (code, got))
        check_summary(vexp, "visible")
        check_lookups(vexp)
        # deliverable /app/summary.json must match the service's summary
        s = read_json("/app/summary.json")
        if s is None or not close_enough(s, vexp["summary"]):
            fail("/app/summary.json does not match the visible summary")

    # ---- hidden cases ----
    for name in sorted(os.listdir(HALL)):
        cdir = os.path.join(HALL, name)
        if os.path.isdir(cdir):
            run_hidden_case(cdir)

    # ---- the deliverable must also run as a live server ----
    proc = subprocess.Popen([sys.executable, "/app/api.py", "8477"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    try:
        ready = False
        for _ in range(50):
            try:
                with urllib.request.urlopen(
                        "http://127.0.0.1:8477/api/v1/health",
                        timeout=2) as r:
                    if r.status == 200:
                        ready = True
                        break
            except Exception:
                time.sleep(0.2)
        if not ready:
            fail("python3 /app/api.py 8477 never served /api/v1/health")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
except Exception as e:
    fail("unexpected verifier error: %r" % e)

if FAIL:
    print("FAILURES (%d)" % len(FAIL))
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS — Quartz Haven OK")
open("/logs/verifier/reward.txt", "w").write("1")
PYEOF
exit 0
