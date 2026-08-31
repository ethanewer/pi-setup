#!/bin/bash
# Verifier for onyx-caravan: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/origin.py and /app/config.json, then EXECUTES the
# deliverable client (/app/solve.py) against freshly launched origins — the
# visible reference deployment and every hidden deployment in /tests/hidden —
# comparing the saved reports against independently computed session values
# and confirming the session is terminated server-side. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_ORIGIN_SHA="d77171811bda71d734900cd98617e3768f8871eee07627f4470448c974b880c6"
PRISTINE_CONFIG_SHA="35ee5a1a4766ed33e251f85e0ee4fab2ed4feb08a6d9dd37ace6e512bd5b1525"

no_modify_broken=0
for pair in "/app/origin.py:$PRISTINE_ORIGIN_SHA" "/app/config.json:$PRISTINE_CONFIG_SHA"; do
    path="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import hashlib
import hmac
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_origin(cfg_path, port):
    proc = subprocess.Popen(
        [sys.executable, "/app/origin.py", cfg_path, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    for _ in range(100):
        try:
            s = socket.create_connection(("127.0.0.1", port), 0.5)
            s.close()
            return proc
        except OSError:
            if proc.poll() is not None:
                return None
            time.sleep(0.05)
    proc.terminate()
    return None


def expected_for(cfg):
    user = cfg["users"][0]
    sid = hmac.new(cfg["sid_secret"].encode(), user["username"].encode(),
                   hashlib.sha256).hexdigest()[:24]
    csrf = hashlib.sha256((sid + ":csrf").encode()).hexdigest()[:16]
    return {"username": user["username"], "logged_in": True, "sid": sid,
            "csrf": csrf, "logged_out": True}


def session_dead(port, cfg, sid):
    req = urllib.request.Request(
        "http://127.0.0.1:%d/panel" % port,
        headers={"Cookie": "%s=%s" % (cfg["cookie_name"], sid)},
    )
    try:
        urllib.request.urlopen(req, timeout=5)
        return False
    except urllib.error.HTTPError as exc:
        return exc.code == 401
    except Exception:
        return False


def check_case(cfg, port, out, expected, label):
    user = cfg["users"][0]
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--origin", "http://127.0.0.1:%d" % port,
             "--username", user["username"], "--password", user["password"],
             "--out", out],
            capture_output=True, text=True, timeout=60,
        )
    except Exception as exc:
        failures.append("%s: client crashed: %s" % (label, exc))
        return
    if r.returncode != 0:
        failures.append("%s: client failed rc=%d %s"
                        % (label, r.returncode, r.stderr[-200:]))
        return
    if not os.path.isfile(out):
        failures.append("%s: no report written" % label)
        return
    try:
        with open(out) as fh:
            got = json.load(fh)
    except Exception:
        failures.append("%s: report unreadable" % label)
        return
    if got != expected:
        failures.append("%s: report mismatch got=%r" % (label, got))
        return
    if not session_dead(port, cfg, expected["sid"]):
        failures.append("%s: session not terminated server-side after logout"
                        % label)


if not failures:
    if not os.path.isfile(SOLVE):
        failures.append("missing /app/solve.py")
    else:
        # --- visible case: fresh origin from the sha-guarded reference config
        if os.path.isfile("/app/config.json"):
            with open("/app/config.json") as fh:
                cfg = json.load(fh)
            port = free_port()
            proc = start_origin("/app/config.json", port)
            if proc is None:
                failures.append("reference origin failed to start")
            else:
                check_case(cfg, port, "/tmp/onyx_visible_out.json",
                           expected_for(cfg), "visible")
                proc.terminate()
                proc.wait()
        else:
            failures.append("missing /app/config.json")

        # --- visible deliverable: /app/answer.json structurally complete ---
        if os.path.isfile("/app/answer.json"):
            try:
                with open("/app/answer.json") as fh:
                    ans = json.load(fh)
                with open("/app/config.json") as fh:
                    cfg = json.load(fh)
                user = cfg["users"][0]
                if not (isinstance(ans, dict)
                        and ans.get("username") == user["username"]
                        and ans.get("logged_in") is True
                        and ans.get("logged_out") is True
                        and isinstance(ans.get("sid"), str) and ans["sid"]
                        and isinstance(ans.get("csrf"), str) and ans["csrf"]):
                    failures.append("answer.json structurally invalid")
            except Exception:
                failures.append("answer.json unreadable")
        else:
            failures.append("missing /app/answer.json")

        # --- hidden cases: distinct deployments with their own configs ---
        hidden_dir = "/tests/hidden"
        if os.path.isdir(hidden_dir):
            cases = sorted(os.listdir(hidden_dir))
            if not cases:
                failures.append("no hidden cases present")
            for c in cases:
                base = os.path.join(hidden_dir, c)
                cfgp = os.path.join(base, "config.json")
                expp = os.path.join(base, "expected.json")
                if not (os.path.isfile(cfgp) and os.path.isfile(expp)):
                    failures.append("hidden '%s' malformed" % c)
                    continue
                with open(cfgp) as fh:
                    cfg = json.load(fh)
                expected = expected_for(cfg)
                try:
                    with open(expp) as fh:
                        if json.load(fh) != expected:
                            failures.append(
                                "hidden '%s': expected.json drift" % c)
                            continue
                except Exception:
                    failures.append(
                        "hidden '%s': expected.json unreadable" % c)
                    continue
                port = free_port()
                proc = start_origin(cfgp, port)
                if proc is None:
                    failures.append("hidden '%s': origin failed to start" % c)
                    continue
                check_case(cfg, port, "/tmp/onyx_hidden_out.json", expected,
                           "hidden '%s'" % c)
                proc.terminate()
                proc.wait()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
