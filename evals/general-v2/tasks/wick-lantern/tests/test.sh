#!/usr/bin/env bash
# Verifier for tasks/wick-lantern (executes-deliverable).
# Checks the /app/jupyter_config.py deliverable textually (documented
# assignment lines, compiles cleanly) and then EXECUTES it: launches
# `jupyter server --config=...` under each hidden port scenario and requires
# the expected bind, a tokenless HTTP 200 on /api/status, and reachability on
# the machine's non-loopback address. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never runs solve.sh.
set -u

mkdir -p /logs/verifier

python3 - <<'PYEOF'
import json
import os
import py_compile
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

CFG = "/app/jupyter_config.py"
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


# --------------------------------------------------- textual + compile checks
if not os.path.isfile(CFG):
    check(False, "missing deliverable %s" % CFG)
    text = ""
else:
    try:
        py_compile.compile(CFG, doraise=True)
    except Exception as exc:
        check(False, "config does not compile: %r" % exc)
    with open(CFG, encoding="utf-8") as fh:
        text = fh.read()
    check("get_config" in text, "config must define c = get_config()")
    for alias in ("ServerApp", "NotebookApp"):
        check(
            re.search(r"c\.%s\.ip\s*=\s*['\"]0\.0\.0\.0['\"]" % alias, text) is not None,
            "missing documented line c.%s.ip = \"0.0.0.0\"" % alias,
        )
        check(
            re.search(r"c\.%s\.port\s*=" % alias, text) is not None,
            "missing documented assignment c.%s.port = ..." % alias,
        )
        check(
            re.search(r"c\.%s\.open_browser\s*=\s*False" % alias, text) is not None,
            "missing documented line c.%s.open_browser = False" % alias,
        )
        check(
            re.search(r"c\.%s\.allow_remote_access\s*=\s*True" % alias, text) is not None,
            "missing documented line c.%s.allow_remote_access = True" % alias,
        )
        check(
            re.search(r"c\.%s\.token\s*=\s*['\"][^'\"]*['\"]" % alias, text) is not None,
            "missing documented assignment c.%s.token = \"\"" % alias,
        )
        check(
            re.search(r"c\.%s\.password\s*=\s*['\"][^'\"]*['\"]" % alias, text) is not None,
            "missing documented assignment c.%s.password = \"\"" % alias,
        )


def container_ip():
    """Best-effort non-loopback IPv4 of this container, or None."""
    try:
        out = subprocess.run(["hostname", "-I"], capture_output=True,
                             text=True, timeout=5).stdout.split()
        for tok in out:
            try:
                socket.inet_aton(tok)
                if not tok.startswith("127."):
                    return tok
            except OSError:
                continue
    except Exception:
        pass
    try:
        ip = socket.gethostbyname(socket.gethostname())
        if not ip.startswith("127."):
            return ip
    except Exception:
        pass
    return None


def kill_all():
    for pat in ("jupyter-server", "bin/jupyter"):
        subprocess.run(["pkill", "-f", pat], capture_output=True)


def launch_case(env_extra, exp_port, label):
    subprocess.run(["mkdir", "-p", "/tmp/wick-lr"], capture_output=True)
    kill_all()
    time.sleep(0.3)
    env = os.environ.copy()
    env.pop("LANTERN_PORT", None)
    env.update(env_extra)
    logf = open("/tmp/wick_srv.log", "ab")
    proc = subprocess.Popen(
        ["jupyter", "server", "--config=%s" % CFG, "--no-browser",
         "--allow-root", "--ServerApp.root_dir=/tmp/wick-lr"],
        stdout=logf, stderr=subprocess.STDOUT, env=env,
    )
    bound = False
    for _ in range(120):
        if proc.poll() is not None:
            break
        try:
            s = socket.create_connection(("127.0.0.1", exp_port), 1)
            s.close()
            bound = True
            break
        except OSError:
            time.sleep(0.5)
    if not bound:
        check(False, "[%s] server never bound 127.0.0.1:%d" % (label, exp_port))
    else:
        # tokenless /api/status must answer 200
        code = None
        try:
            with urllib.request.urlopen(
                    "http://127.0.0.1:%d/api/status" % exp_port, timeout=5) as resp:
                code = resp.status
        except urllib.error.HTTPError as exc:
            code = exc.code
        except Exception as exc:
            code = "ERR:%r" % exc
        check(code == 200,
              "[%s] /api/status code=%r (expected 200; token auth must be off)"
              % (label, code))
        # true all-interfaces bind: reachable via non-loopback address
        ip = container_ip()
        if ip is None:
            print("note: no non-loopback container IP; skipping broad-bind check",
                  flush=True)
        else:
            okb = False
            try:
                s = socket.create_connection((ip, exp_port), 3)
                s.close()
                okb = True
            except OSError:
                okb = False
            check(okb, "[%s] not reachable on non-loopback %s:%d "
                       "(ip must be 0.0.0.0)" % (label, ip, exp_port))
    try:
        proc.terminate()
        proc.wait(timeout=10)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass
    logf.close()
    kill_all()
    time.sleep(0.3)


# ------------------------------------------------------------ hidden scenarios
hidden_dir = "/tests/hidden"
cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
if not cases:
    check(False, "no hidden cases present")
for c in cases:
    base = os.path.join(hidden_dir, c)
    try:
        with open(os.path.join(base, "env.json")) as fh:
            envj = json.load(fh)
        with open(os.path.join(base, "expected.json")) as fh:
            expj = json.load(fh)
    except Exception as exc:
        check(False, "hidden case '%s' malformed: %r" % (c, exc))
        continue
    extra = envj.get("env", {}) if isinstance(envj, dict) else {}
    if not isinstance(extra, dict):
        check(False, "hidden case '%s': env.json 'env' must be an object" % c)
        continue
    port = expj.get("port") if isinstance(expj, dict) else None
    if not isinstance(port, int) or not (1 <= port <= 65535):
        check(False, "hidden case '%s': bad expected port %r" % (c, port))
        continue
    launch_case(extra, port, c)

# ------------------------------------------------------------------- reward
if failures:
    print("FAILURES:")
    for msg in failures:
        print("  - " + msg)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS")
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PYEOF
