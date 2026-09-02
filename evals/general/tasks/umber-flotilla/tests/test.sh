#!/bin/bash
# Verifier for umber-flotilla (executes-deliverable).
#
# 1. Checks the no-modify rule on the shipped visible fixture.
# 2. Compares the /app/summary.json deliverable against the reference.
# 3. STARTS the deliverable /app/service.py and replays every hidden case in
#    /tests/hidden against the live service (scale/edge/zero/empty/error).
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_FIXTURE_SHA="e4d7632dd9db68b8cb66f0a9752e15418ab910e7cbe5ea91fa3d8400dd8713f5"

if [ ! -f /app/portfolio_visible.json ]; then
    echo "no-modify: /app/portfolio_visible.json missing" >&2
else
    actual="$(sha256sum /app/portfolio_visible.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_FIXTURE_SHA" ]; then
        echo "no-modify: /app/portfolio_visible.json was modified" >&2
    fi
fi

python3 - <<'PY'
import json, math, os, subprocess, sys, time, urllib.error, urllib.request

SOLVE = "/app/service.py"
PORT = 8123
BASE = "http://127.0.0.1:%d" % PORT
failures = []


def norm(x):
    """Round floats recursively to 4 dp for float-order-insensitive compare."""
    if isinstance(x, bool):
        return x
    if isinstance(x, float):
        if not math.isfinite(x):
            return repr(x)
        return round(x, 4)
    if isinstance(x, int):
        return x
    if isinstance(x, dict):
        return {k: norm(v) for k, v in x.items()}
    if isinstance(x, list):
        return [norm(v) for v in x]
    return x


def req(method, path, body=None, raw=None):
    if raw is not None:
        data = raw.encode()
    elif body is not None:
        data = json.dumps(body).encode()
    else:
        data = None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


if not os.path.isfile(SOLVE):
    failures.append("missing /app/service.py")
else:
    # ---- start the delivered service ----
    log = open("/tmp/umber_verify_service.log", "w")
    proc = subprocess.Popen([sys.executable, SOLVE, str(PORT)],
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
        failures.append("service did not come up on :%d" % PORT)
        proc.kill()
    else:
        # ---- /app/summary.json deliverable vs reference for visible fixture ----
        exp_path = "/tests/expected.json"
        if not os.path.isfile("/app/summary.json"):
            failures.append("missing /app/summary.json")
        else:
            try:
                with open("/app/summary.json") as f:
                    got = json.load(f)
                with open(exp_path) as f:
                    want = json.load(f)
                if norm(got) != norm(want):
                    failures.append("/app/summary.json does not match reference")
            except Exception as e:
                failures.append("/app/summary.json unreadable: %r" % e)

        # ---- hidden portfolio cases driven through the live service ----
        hidden = "/tests/hidden"
        for case in sorted(os.listdir(hidden)):
            base = os.path.join(hidden, case)
            pf = os.path.join(base, "portfolio.json")
            ef = os.path.join(base, "expected.json")
            if not (os.path.isfile(pf) and os.path.isfile(ef)):
                continue  # errors/cases.json handled below
            try:
                with open(pf) as f:
                    payload = json.load(f)
                with open(ef) as f:
                    want = json.load(f)
            except Exception as e:
                failures.append("hidden '%s' unreadable: %r" % (case, e))
                continue
            try:
                st, _ = req("POST", "/api/v1/portfolios", body=payload)
                if st != 201:
                    failures.append("hidden '%s': POST status %d != 201"
                                    % (case, st))
                    continue
                st, body = req("GET",
                               "/api/v1/portfolios/%s/summary"
                               % urllib.request.quote(payload["id"], safe=""))
                if st != 200:
                    failures.append("hidden '%s': summary status %d != 200"
                                    % (case, st))
                    continue
                got = json.loads(body.decode())
                if norm(got) != norm(want):
                    failures.append("hidden '%s': summary mismatch" % case)
            except Exception as e:
                failures.append("hidden '%s': exception %r" % (case, e))

        # ---- hidden error/status cases ----
        errf = os.path.join(hidden, "errors", "cases.json")
        if os.path.isfile(errf):
            with open(errf) as f:
                cases = json.load(f)
            for c in cases:
                label = c.get("label", "?")
                path = c.get("path", "/api/v1/portfolios")
                try:
                    method = c.get("method", "POST")
                    if "raw" in c:
                        st, _ = req(method, path, raw=c["raw"])
                    elif "body" in c:
                        st, _ = req(method, path, body=c["body"])
                    else:
                        st, _ = req(method, path)
                    if st != c["expect_status"]:
                        failures.append("error case '%s': status %d != %d"
                                        % (label, st, c["expect_status"]))
                except Exception as e:
                    failures.append("error case '%s': exception %r" % (label, e))

        # ---- live service must also reproduce the visible summary ----
        try:
            with open("/app/portfolio_visible.json") as f:
                vis = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            st, _ = req("POST", "/api/v1/portfolios", body=vis)
            if st != 201:
                failures.append("visible replay POST status %d != 201" % st)
            else:
                st, body = req("GET", "/api/v1/portfolios/visible-fleet/summary")
                got = json.loads(body.decode()) if st == 200 else None
                if got is None or norm(got) != norm(want):
                    failures.append("live visible summary mismatch")
        except Exception as e:
            failures.append("visible replay exception %r" % e)

        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
    log.close()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
