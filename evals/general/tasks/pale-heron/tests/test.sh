#!/bin/bash
# pale-heron verifier (executes-deliverable).
# Content-checks the agent's Jupyter Server config, then genuinely launches
# `jupyter server --config=...` under every hidden deploy-descriptor scenario,
# requiring the correct loopback bind and a tokenless HTTP 200 from /api/status.
# Writes REWARD (0/1) to /logs/verifier/reward.txt. Never runs solve.sh.
set -u

mkdir -p /logs/verifier
reward=0

CFG=/app/notebook_server_config.py
DESC=/app/nb_deploy.json
BAK=/tmp/ph_desc.bak

cleanup() {
    pkill -f "jupyter-server" 2>/dev/null || true
    pkill -f "/usr/local/bin/jupyter" 2>/dev/null || true
    sleep 0.2
}
cleanup

python3 - "$CFG" "$DESC" "$BAK" <<'PY'
import json
import os
import py_compile
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

cfg_path, desc_path, bak_path = sys.argv[1], sys.argv[2], sys.argv[3]
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


# ------------------------------------------------------------ file-content gate
check(os.path.isfile(cfg_path), "missing deliverable %s" % cfg_path)
if os.path.isfile(cfg_path):
    try:
        py_compile.compile(cfg_path, cfile="/tmp/ph_cfg.pyc", doraise=True)
    except Exception as exc:
        failures.append("config does not compile: %r" % exc)
    try:
        with open(cfg_path) as fh:
            src = fh.read()
    except Exception as exc:
        src = ""
        failures.append("config unreadable: %r" % exc)
    check("port_retries" in src, "config lacks a port_retries assignment")
    check("ServerApp" in src, "config does not configure ServerApp")
    check("NotebookApp" in src, "config does not configure NotebookApp")
    check("nb_deploy.json" in src, "config does not reference the deploy descriptor")

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

# ------------------------------------------------------------- hidden launches
HIDDEN = "/tests/hidden"
cases = sorted(d for d in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, d))) if os.path.isdir(HIDDEN) else []
check(bool(cases), "no hidden deploy cases present")


def launch_and_probe(exp_port):
    """Start jupyter with the agent config; return (bound_ok, http_code)."""
    os.makedirs("/tmp/ph_root", exist_ok=True)
    log = open("/tmp/ph_srv.log", "w")
    proc = subprocess.Popen(
        ["jupyter", "server", "--config=/app/notebook_server_config.py",
         "--no-browser", "--allow-root", "--ServerApp.root_dir=/tmp/ph_root"],
        stdout=log, stderr=log)
    bound = False
    try:
        deadline = time.time() + 30
        while time.time() < deadline:
            if proc.poll() is not None:
                break  # server died (bad config / refused bind)
            try:
                s = socket.create_connection(("127.0.0.1", exp_port), 1)
                s.close()
                bound = True
                break
            except OSError:
                time.sleep(0.4)
        code = None
        if bound:
            try:
                with urllib.request.urlopen(
                        "http://127.0.0.1:%d/api/status" % exp_port, timeout=5) as resp:
                    code = resp.status
            except urllib.error.HTTPError as exc:
                code = exc.code
            except Exception:
                code = None
        return bound, code
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        log.close()


had_desc = os.path.isfile(desc_path)
for case in cases:
    base = os.path.join(HIDDEN, case)
    exp_path = os.path.join(base, "expected.json")
    try:
        with open(exp_path) as fh:
            exp = json.load(fh)
        exp_port = int(exp["port"])
    except Exception as exc:
        failures.append("case %s: unreadable expected.json: %r" % (case, exc))
        continue

    # rotate the deploy descriptor for this case
    desc_file = os.path.join(base, "nb_deploy.json")
    if os.path.isfile(desc_file):
        if had_desc:
            shutil.copyfile(desc_path, bak_path)
            had_desc = True
        shutil.copyfile(desc_file, desc_path)
        descriptor_absent = False
    else:
        if os.path.isfile(desc_path):
            shutil.move(desc_path, bak_path)
            had_desc = True
        descriptor_absent = True

    try:
        bound, code = launch_and_probe(exp_port)
        if not bound:
            failures.append("case %s: server never bound 127.0.0.1:%d "
                            "(see /tmp/ph_srv.log)" % (case, exp_port))
        elif code != 200:
            failures.append("case %s: /api/status on port %d gave %r, want 200"
                            % (case, exp_port, code))
    finally:
        # restore the original descriptor state
        if descriptor_absent:
            if os.path.isfile(bak_path):
                shutil.move(bak_path, desc_path)
        else:
            if os.path.isfile(bak_path):
                shutil.move(bak_path, desc_path)
            elif had_desc and not os.path.isfile(desc_path):
                pass  # original descriptor was the case file; leave as-is

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS")
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PY
rc=$?

pkill -f "jupyter-server" 2>/dev/null || true
[ "$rc" -eq 0 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
