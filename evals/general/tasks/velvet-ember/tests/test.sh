#!/bin/bash
# Verifier for velvet-ember (executes-deliverable).
# Executes /app/normalize.py (function level + CLI on hidden inputs) and
# /app/gateway.py (WSGI direct + live server) against hidden cases, checks the
# /app/canonical_map.json deliverable, and writes REWARD to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

for f in /app/normalize.py /app/gateway.py /app/canonical_map.json; do
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


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


# Import must not start a server; guard with an alarm.
try:
    import signal

    def _alarm(signum, frame):
        raise TimeoutError("import timed out (server started on import?)")

    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(20)
    norm = load_module("ve_normalize", "/app/normalize.py")
    gw = load_module("ve_gateway", "/app/gateway.py")
    signal.alarm(0)
except Exception as e:
    print("fatal: cannot import deliverables: %s" % e)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

if not hasattr(norm, "canonical_header"):
    fail("/app/normalize.py does not expose canonical_header")
if not (hasattr(norm, "HeaderError") and
        issubclass(getattr(norm, "HeaderError", type), ValueError)):
    fail("/app/normalize.py HeaderError must be a ValueError subclass")
if not hasattr(gw, "application"):
    fail("/app/gateway.py does not expose WSGI callable 'application'")


def call_wsgi(app, method, path, raw=b""):
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
    chunks = app(env, lambda s, h, e=None: out.update(s=s))
    data = b"".join(chunks)
    code = int(out["s"].split()[0])
    try:
        parsed = json.loads(data.decode("utf-8"))
    except Exception:
        parsed = None
    return code, parsed


HeaderError = getattr(norm, "HeaderError", ValueError)

# ---- 1. function-level normalization matrix (hidden) ----
ncase = read_json("/tests/hidden/normalization_1/cases.json")
nexp = read_json("/tests/hidden/normalization_1/expected.json")
if ncase and nexp:
    for entry, want in zip(ncase["inputs"], nexp["outputs"]):
        try:
            got = norm.canonical_header(entry)
            raised = False
        except HeaderError:
            raised, got = True, None
        except Exception as e:
            fail("canonical_header(%r) raised %r instead of HeaderError"
                 % (entry, e))
            continue
        if want["ok"]:
            if raised:
                fail("canonical_header(%r) raised for a benign name" % (entry,))
            elif got != want["canonical"]:
                fail("canonical_header(%r)=%r want %r (wrong canonical form)"
                     % (entry, got, want["canonical"]))
        else:
            if not raised:
                fail("canonical_header(%r) returned %r, want HeaderError"
                     % (entry, got))

# ---- 2. CLI deliverable on the hidden normalization inputs ----
if ncase and nexp:
    with open("/tmp/ve_cli_in.json", "w", encoding="utf-8") as fh:
        json.dump(ncase["inputs"], fh)
    try:
        r = subprocess.run([sys.executable, "/app/normalize.py",
                            "/tmp/ve_cli_in.json", "/tmp/ve_cli_out.json"],
                           capture_output=True, text=True, timeout=60)
        got = read_json("/tmp/ve_cli_out.json") if r.returncode == 0 else None
        if got is None:
            fail("normalize.py CLI failed (rc=%d, stderr=%s)"
                 % (r.returncode, r.stderr[:200]))
        elif got != nexp["outputs"]:
            bad = [i for i, (g, w) in enumerate(zip(got, nexp["outputs"]))
                   if g != w][:5]
            fail("CLI output mismatch at entries %r" % bad)
    except subprocess.TimeoutExpired:
        fail("normalize.py CLI timed out")

# ---- 3. gateway behaviour (hidden steps, WSGI direct) ----
gcase = read_json("/tests/hidden/gateway_1/cases.json")
if gcase:
    for i, step in enumerate(gcase["steps"]):
        if "raw_body" in step:
            raw = step["raw_body"].encode()
        else:
            raw = json.dumps(step.get("body")).encode()
        code, body = call_wsgi(gw.application, step["method"], step["path"],
                               raw)
        if code != step["expect_status"]:
            fail("step %d %s %s -> %d, want %d"
                 % (i, step["method"], step["path"], code,
                    step["expect_status"]))
            continue
        if code == 200:
            if body != step.get("expect_body"):
                fail("step %d body %r want %r"
                     % (i, body, step.get("expect_body")))
        elif step.get("expect_error_code"):
            if not (isinstance(body, dict) and
                    body.get("error", {}).get("code") ==
                    step["expect_error_code"]):
                fail("step %d error body %r, want code %s"
                     % (i, body, step["expect_error_code"]))

# ---- 4. visible deliverable /app/canonical_map.json ----
vexp = read_json("/tests/expected.json")
cmap = read_json("/app/canonical_map.json")
if vexp is not None and cmap is None:
    fail("/app/canonical_map.json unreadable")
elif vexp is not None and cmap != vexp:
    fail("/app/canonical_map.json does not match the visible expected map")

# ---- 5. the relay must also serve live ----
proc = subprocess.Popen([sys.executable, "/app/gateway.py", "8123"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    ready = False
    for _ in range(50):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8123/relay/health",
                                        timeout=2) as r:
                if r.status == 200:
                    ready = True
                    break
        except Exception:
            time.sleep(0.2)
    if not ready:
        fail("python3 /app/gateway.py 8123 never served /relay/health")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()

if FAIL:
    print("FAILURES (%d)" % len(FAIL))
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS — Velvet Ember OK")
open("/logs/verifier/reward.txt", "w").write("1")
PYEOF
exit 0
