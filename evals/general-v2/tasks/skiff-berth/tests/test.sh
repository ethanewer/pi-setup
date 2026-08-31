#!/bin/bash
# Verifier for skiff-berth:
#  1. enforces the no-modify rule on the gateway fixture,
#  2. EXECUTES /app/hashgen.py on the visible secret and on every hidden
#     secret in /tests/hidden, crypt-verifying each emitted hash,
#  3. crypt-verifies the submitted /app/credentials.json,
#  4. re-runs /app/provision.sh (idempotency) and re-checks credentials,
#  5. starts /app/gateway.py and probes it over HTTP (health / disabled-auth
#     behavior / 401 on bad creds / 200 on the configured secret).
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

SECRET="TideRope-31Quay"
USER="harbormaster"

# Pristine sha256 of the supplied gateway fixture (the instruction forbids
# modifying it; editing the server to bypass auth is a hard fail).
PRISTINE_GW_SHA="94bc6ab40087ec95bfcd854ac2702b93993f35eb1bd69c9351d80cf4a3d0d3d0"
ACTUAL_GW="$(sha256sum /app/gateway.py 2>/dev/null | awk '{print $1}')"

python3 - "$SECRET" "$USER" "$ACTUAL_GW" "$PRISTINE_GW_SHA" <<'PY'
import base64
import crypt
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SECRET, USER, actual_gw, pristine_gw = sys.argv[1:5]
SOLVE_HASHGEN = "/app/hashgen.py"
SOLVE_PROVISION = "/app/provision.sh"
SOLVE_CREDS = "/app/credentials.json"
GATEWAY = "/app/gateway.py"

failures = []


def check_hashgen(secret, label):
    out = "/tmp/skiff_hashgen_%s.json" % label
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE_HASHGEN, secret, out],
            capture_output=True, text=True, timeout=60,
        )
        if r.returncode != 0:
            return "exit %d" % r.returncode
        with open(out) as fh:
            rec = json.load(fh)
        if list(rec.keys()) != ["algo", "hash"]:
            return "keys %r" % (list(rec.keys()),)
        if rec["algo"] != "sha512_crypt":
            return "algo %r" % rec["algo"]
        h = rec["hash"]
        if not isinstance(h, str) or not h.startswith("$6$"):
            return "hash not sha512-crypt"
        if secret in h:
            return "hash contains plaintext secret"
        if crypt.crypt(secret, h) != h:
            return "crypt verification failed"
        return None
    except Exception as e:
        return "exception: %r" % (e,)


def check_credentials_file():
    try:
        with open(SOLVE_CREDS) as fh:
            creds = json.load(fh)
        if list(creds.keys()) != ["enabled", "users"]:
            return "top-level keys %r" % (list(creds.keys()),)
        if creds["enabled"] is not True:
            return "auth not enabled"
        users = creds["users"]
        if not isinstance(users, dict) or USER not in users:
            return "no %r user" % USER
        rec = users[USER]
        if list(rec.keys()) != ["algo", "hash"]:
            return "user record keys %r" % (list(rec.keys()),)
        if rec["algo"] != "sha512_crypt":
            return "algo %r" % rec["algo"]
        h = rec["hash"]
        if not isinstance(h, str) or not h.startswith("$6$"):
            return "hash not sha512-crypt (locked or malformed)"
        if SECRET in h:
            return "hash contains plaintext secret"
        if crypt.crypt(SECRET, h) != h:
            return "crypt verification failed"
        return None
    except Exception as e:
        return "exception: %r" % (e,)


# 1. gateway fixture must be untouched
if actual_gw != pristine_gw:
    failures.append("gateway fixture was modified or is missing")

# 2. hashgen on the visible secret and every hidden secret
if not os.path.isfile(SOLVE_HASHGEN):
    failures.append("missing /app/hashgen.py")
else:
    err = check_hashgen(SECRET, "visible")
    if err:
        failures.append("hashgen visible secret: %s" % err)
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            sp = os.path.join(hidden_dir, c, "secret.txt")
            if not os.path.isfile(sp):
                failures.append("hidden '%s' malformed" % c)
                continue
            with open(sp) as fh:
                sec = fh.read().strip()
            if not sec:
                failures.append("hidden '%s' empty secret" % c)
                continue
            err = check_hashgen(sec, c)
            if err:
                failures.append("hashgen hidden '%s': %s" % (c, err))

# 3. submitted credentials.json must crypt-verify
if not os.path.isfile(SOLVE_CREDS):
    failures.append("missing /app/credentials.json")
else:
    err = check_credentials_file()
    if err:
        failures.append("credentials.json: %s" % err)

# 4. idempotency: re-run provision.sh, credentials must still verify
if os.path.isfile(SOLVE_PROVISION) and os.access(SOLVE_PROVISION, os.X_OK):
    try:
        r = subprocess.run(["bash", SOLVE_PROVISION],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            failures.append("provision.sh re-run exit %d" % r.returncode)
        else:
            err = check_credentials_file()
            if err:
                failures.append("after re-run, credentials.json: %s" % err)
    except Exception as e:
        failures.append("provision.sh re-run exception: %r" % (e,))
else:
    failures.append("missing or non-executable /app/provision.sh")

# 5. start the gateway and probe over HTTP
def http_get(url, auth=None):
    req = urllib.request.Request(url)
    if auth is not None:
        tok = base64.b64encode(auth.encode()).decode()
        req.add_header("Authorization", "Basic " + tok)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, None


if not failures:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    proc = subprocess.Popen([sys.executable, GATEWAY, str(port)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        base = "http://127.0.0.1:%d" % port
        ok = False
        for _ in range(50):
            try:
                code, _ = http_get(base + "/health")
                if code == 200:
                    ok = True
                    break
            except Exception:
                time.sleep(0.1)
        if not ok:
            failures.append("gateway /health never returned 200")
        else:
            code, _ = http_get(base + "/toll?gate=3")
            if code != 401:
                failures.append("unauthenticated /toll -> %d (want 401)" % code)
            code, _ = http_get(base + "/toll?gate=3", auth=USER + ":WrongPass-1")
            if code != 401:
                failures.append("wrong password -> %d (want 401)" % code)
            code, _ = http_get(base + "/toll?gate=3", auth="nobody:" + SECRET)
            if code != 401:
                failures.append("unknown user -> %d (want 401)" % code)
            code, body = http_get(base + "/toll?gate=3", auth=USER + ":" + SECRET)
            if code != 200 or not (isinstance(body, dict)
                                   and body.get("status") == "ok"):
                failures.append("configured secret rejected -> %d %r" % (code, body))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
