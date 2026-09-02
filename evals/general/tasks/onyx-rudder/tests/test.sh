#!/bin/bash
# Verifier for onyx-rudder (executes-deliverable).
#
# 1. Checks the no-modify rule on the shipped /app/header_scan.json fixture.
# 2. Compares the /app/scan_report.json deliverable against the reference.
# 3. Imports /app/hdrnorm.py and runs the hidden canonical_header matrix.
# 4. Re-runs the /app/hdrnorm.py scan CLI on a hidden scan input.
# 5. STARTS the deliverable /app/gateway.py and drives the hidden gateway
#    cases through the live HTTP surface.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_SCAN_SHA="e33151a78bccd2c6fb12004f76ad109f45d8aa345042cdf3f62632c265558647"

if [ ! -f /app/header_scan.json ]; then
    echo "no-modify: /app/header_scan.json missing" >&2
else
    actual="$(sha256sum /app/header_scan.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SCAN_SHA" ]; then
        echo "no-modify: /app/header_scan.json was modified" >&2
    fi
fi

python3 - <<'PY'
import importlib.util, json, os, subprocess, sys, time, urllib.error, urllib.request

PORT = 8211
BASE = "http://127.0.0.1:%d" % PORT
failures = []


def load_module():
    spec = importlib.util.spec_from_file_location("hdrnorm", "/app/hdrnorm.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def check(condition, msg):
    if not condition:
        failures.append(msg)


ok = True

# ---- 1. module matrix ----
try:
    mod = load_module()
    fn = getattr(mod, "canonical_header", None)
    check(callable(fn), "missing callable canonical_header in /app/hdrnorm.py")
    if callable(fn):
        cases_file = "/tests/hidden/module/cases.json"
        with open(cases_file) as f:
            cases = json.load(f)
        for name, expected in cases:
            try:
                got = fn(name)
                if expected == "ERROR":
                    failures.append("canonical_header(%r) accepted, expected "
                                    "ValueError" % (name,))
                elif got != expected:
                    failures.append("canonical_header(%r) = %r, expected %r"
                                    % (name, got, expected))
            except ValueError:
                if expected != "ERROR":
                    failures.append("canonical_header(%r) raised ValueError, "
                                    "expected %r" % (name, expected))
            except Exception as e:
                failures.append("canonical_header(%r) raised %r" % (name, e))
except Exception as e:
    ok = False
    failures.append("could not import /app/hdrnorm.py: %r" % e)

# ---- 2. scan deliverable + hidden scan CLI run ----
try:
    with open("/app/scan_report.json") as f:
        got = json.load(f)
    with open("/tests/expected.json") as f:
        want = json.load(f)
    check(got == want, "/app/scan_report.json does not match reference scan")
except Exception as e:
    failures.append("/app/scan_report.json unreadable: %r" % e)

if ok:
    out_tmp = "/tmp/onyx_hidden_scan_out.json"
    try:
        if os.path.exists(out_tmp):
            os.remove(out_tmp)
        r = subprocess.run([sys.executable, "/app/hdrnorm.py", "scan",
                            "/tests/hidden/scan/in.json", out_tmp],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            failures.append("scan CLI exited %d on hidden scan input"
                            % r.returncode)
        else:
            with open(out_tmp) as f:
                got = json.load(f)
            with open("/tests/hidden/scan/expected.json") as f:
                want = json.load(f)
            check(got == want, "hidden scan CLI output mismatch")
    except Exception as e:
        failures.append("hidden scan CLI exception %r" % e)

# ---- 3. gateway service ----
if ok and os.path.isfile("/app/gateway.py"):
    log = open("/tmp/onyx_verify_gateway.log", "w")
    proc = subprocess.Popen([sys.executable, "/app/gateway.py", str(PORT)],
                            stdout=log, stderr=log)
    up = False
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            st, _ = req("GET", "/api/v1/health")
            if st == 200:
                up = True
                break
        except Exception:
            time.sleep(0.2)
    if not up:
        failures.append("gateway did not come up on :%d" % PORT)
        proc.kill()
    else:
        with open("/tests/hidden/gateway/cases.json") as f:
            cases = json.load(f)
        for c in cases:
            label = c.get("label", "?")
            try:
                st, body = req(c["method"], c["path"], body=c["body"])
                check(st == c["expect_status"],
                      "gateway '%s': status %d != %d"
                      % (label, st, c["expect_status"]))
                if "expect_rewritten" in c and st == 200:
                    got = json.loads(body.decode())
                    check(got.get("rewritten") == c["expect_rewritten"],
                          "gateway '%s': rewritten mismatch" % label)
                if "expect_results" in c and st == 200:
                    got = json.loads(body.decode())
                    check(got.get("results") == c["expect_results"],
                          "gateway '%s': results mismatch" % label)
            except Exception as e:
                failures.append("gateway '%s': exception %r" % (label, e))
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
    log.close()
elif ok:
    failures.append("missing /app/gateway.py")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
