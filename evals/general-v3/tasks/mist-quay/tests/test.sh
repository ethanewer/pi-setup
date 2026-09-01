#!/bin/bash
# Verifier for mist-quay: guards the pristine fixture, re-runs the agent's
# /app/configure.sh (idempotence), checks htpasswd hashing rules, then probes
# the live service over loopback HTTP for the visible account and for hidden
# accounts created through the agent's /app/adduser.sh.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_SERVER_SHA="9edbc5dc8961d3b710e47c85885066bb12b05703d3d8d3f42f9e2cbb0fecbd94"

fixture_broken=0
if [ ! -f /app/service/server.py ]; then
    echo "no-modify: /app/service/server.py missing" >&2
    fixture_broken=1
else
    actual="$(sha256sum /app/service/server.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SERVER_SHA" ]; then
        echo "no-modify: /app/service/server.py was modified" >&2
        fixture_broken=1
    fi
fi
if [ ! -f /app/service/config.ini ]; then
    echo "no-modify: /app/service/config.ini missing" >&2
    fixture_broken=1
fi

python3 - "$fixture_broken" <<'PY'
import base64, configparser, crypt, os, re, subprocess, sys, time, urllib.error, urllib.request

fixture_broken = int(sys.argv[1])
failures = []
if fixture_broken:
    failures.append("/app/service fixtures missing or modified (no-modify rule)")

CFG = "/app/service/config.ini"
HT = "/app/service/users.htpasswd"
PORT = 8731
BASE = "http://127.0.0.1:%d/" % PORT
OPERATOR = "marlow"
SECRET = "MistQuay#Runnel-52"


def http_get(user=None, password=None):
    req = urllib.request.Request(BASE)
    if user is not None:
        token = base64.b64encode(("%s:%s" % (user, password)).encode()).decode()
        req.add_header("Authorization", "Basic " + token)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def load_ht():
    entries = {}
    try:
        with open(HT, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                u, _, h = line.partition(":")
                entries.setdefault(u, []).append(h)
    except Exception as e:
        failures.append("users.htpasswd unreadable: %s" % e)
    return entries


def check_ht_entry(entries, user, password, label):
    hs = entries.get(user)
    if not hs:
        failures.append("%s: no entry for user %s" % (label, user))
        return
    if len(hs) > 1:
        failures.append("%s: duplicate entries for %s" % (label, user))
    h = hs[0]
    if not h.startswith("$6$"):
        failures.append("%s: hash for %s is not SHA-512 crypt ($6$): %r"
                        % (label, user, h[:10]))
    try:
        if crypt.crypt(password, h) != h:
            failures.append("%s: crypt verification failed for %s" % (label, user))
    except Exception as e:
        failures.append("%s: crypt raised for %s: %s" % (label, user, e))


# --- deliverable presence + executability
for d in ("/app/configure.sh", "/app/adduser.sh"):
    if not (os.path.isfile(d) and os.access(d, os.X_OK)):
        failures.append("missing or not executable: %s" % d)

if not failures:
    # --- idempotence: re-run configure.sh from the deployed state
    r = subprocess.run(["/app/configure.sh"], capture_output=True, text=True,
                       timeout=60)
    if r.returncode != 0:
        failures.append("configure.sh re-run exited %d: %s"
                        % (r.returncode, r.stderr[-400:]))

    # --- enabled flag (guarded parse)
    try:
        cfg = configparser.ConfigParser()
        with open(CFG) as fh:
            cfg.read_file(fh)
        if cfg.get("auth", "enabled", fallback="").strip().lower() != "true":
            failures.append("config.ini: auth.enabled is not true")
    except Exception as e:
        failures.append("config.ini unreadable: %s" % e)

    # --- operator entry + no plaintext secret anywhere in the file
    entries = load_ht()
    check_ht_entry(entries, OPERATOR, SECRET, "visible")
    try:
        with open(HT, "r", encoding="utf-8") as fh:
            body = fh.read()
        if SECRET in body:
            failures.append("plaintext secret present in users.htpasswd")
    except Exception:
        pass

    # --- hidden accounts through the agent's adduser.sh
    hidden = "/tests/hidden"
    cases = []
    if os.path.isdir(hidden):
        for c in sorted(os.listdir(hidden)):
            p = os.path.join(hidden, c, "creds.txt")
            if os.path.isfile(p):
                try:
                    with open(p) as fh:
                        line = fh.read().strip()
                    u, _, pw = line.partition(" ")
                    if u and pw:
                        cases.append((c, u, pw))
                except Exception as e:
                    failures.append("hidden '%s': creds unreadable: %s" % (c, e))
    if not cases:
        failures.append("no hidden cases present")
    for c, u, pw in cases:
        r = subprocess.run(["/app/adduser.sh", u, pw],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            failures.append("hidden '%s': adduser.sh exited %d: %s"
                            % (c, r.returncode, r.stderr[-300:]))
    entries = load_ht()
    for c, u, pw in cases:
        check_ht_entry(entries, u, pw, "hidden-'%s'" % c)
    check_ht_entry(entries, OPERATOR, SECRET, "visible-after-hidden")

    # --- live HTTP probes (loopback)
    if not failures:
        proc = subprocess.Popen([sys.executable, "/app/service/server.py"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        ready = False
        for _ in range(50):
            try:
                http_get()
                ready = True
                break
            except Exception:
                time.sleep(0.1)
        if not ready:
            failures.append("service did not become ready on port %d" % PORT)
        else:
            def probe(label, user, password, want_status, want_body):
                st, body = http_get(user, password)
                if st != want_status or want_body not in body:
                    failures.append("%s: got %d %r, want %d containing %r"
                                    % (label, st, body[:40], want_status,
                                       want_body))
            probe("no-credentials", None, None, 401, "")
            probe("wrong-password", OPERATOR, SECRET + "x", 401, "")
            probe("correct-operator", OPERATOR, SECRET, 200, "cove-ok")
            for c, u, pw in cases:
                probe("hidden-'%s'-wrong" % c, u, pw + "x", 401, "")
                probe("hidden-'%s'-correct" % c, u, pw, 200, "cove-ok")
            # auth must actually be ON: a disabled server returns 200 for all
            st, body = http_get()
            if st == 200 and "auth-disabled" in body:
                failures.append("auth still disabled (auth-disabled body)")
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:
            proc.kill()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
