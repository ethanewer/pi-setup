#!/bin/bash
# drift-marsh verifier (executes-deliverable).
# Independently parses the agent's two Kelpline property files against the
# designated values, then genuinely boots the cluster with start_cluster.sh —
# both on the visible /app/conf configuration and on every hidden alternative
# configuration directory (valid ports must listen; a broken config must make
# the script exit non-zero). Writes REWARD (0/1) to /logs/verifier/reward.txt.
# Never runs solve.sh.
set -u

mkdir -p /logs/verifier
reward=0
pkill -f "kelp_daemon.py" 2>/dev/null || true
sleep 0.2

python3 - <<'PY'
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

failures = []
CORE = "/app/conf/core.properties"
SITE = "/app/conf/site.properties"
START = "/app/start_cluster.sh"
DAEMON = "/app/bin/kelp_daemon.py"


def check(cond, msg):
    if not cond:
        failures.append(msg)


def load_props(path):
    """Independent Kelpline properties parser (key = value, # comments)."""
    props = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("!"):
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            props[key.strip()] = val.strip()
    return props


def listening(addr, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((addr, port))
        return True
    except Exception:
        return False
    finally:
        try:
            s.close()
        except Exception:
            pass


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False


# ------------------------------------------------------------ deliverable gate
for path in (CORE, SITE, START):
    check(os.path.isfile(path), "missing deliverable %s" % path)
check(os.access(START, os.X_OK) if os.path.isfile(START) else False,
      "start_cluster.sh is not executable")

core = site = {}
try:
    core = load_props(CORE)
except Exception as exc:
    check(False, "core.properties unreadable: %r" % exc)
try:
    site = load_props(SITE)
except Exception as exc:
    check(False, "site.properties unreadable: %r" % exc)

# designated values (textual check on the exact config strings)
check(core.get("kelpline.node.address") == "127.0.0.1",
      "kelpline.node.address != 127.0.0.1 (%r)" % core.get("kelpline.node.address"))
check(core.get("kelpline.rpc.port") == "24418",
      "kelpline.rpc.port != 24418 (%r)" % core.get("kelpline.rpc.port"))
check(site.get("kelpline.role.master") == "namenode",
      "kelpline.role.master != namenode (%r)" % site.get("kelpline.role.master"))
check(site.get("kelpline.role.worker") == "datanode",
      "kelpline.role.worker != datanode (%r)" % site.get("kelpline.role.worker"))
check(site.get("kelpline.replication.factor") == "1",
      "kelpline.replication.factor != 1 (%r)" % site.get("kelpline.replication.factor"))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# --------------------------------------------------- visible boot + listening
r = subprocess.run(["bash", START], capture_output=True, text=True, timeout=150)
check(r.returncode == 0, "start_cluster.sh rc=%s stderr=%s"
      % (r.returncode, (r.stderr or "")[-300:]))
check("KELP_CLUSTER_UP" in (r.stdout or ""),
      "start_cluster.sh did not print KELP_CLUSTER_UP (stdout=%r)" % (r.stdout or "")[-200:])

run_dir = "/app/run"
for role, port in (("namenode", 24418), ("datanode", 24419)):
    marker = os.path.join(run_dir, role + ".ready")
    check(os.path.isfile(marker), "no ready marker for %s" % role)
    pid = None
    try:
        with open(os.path.join(run_dir, role + ".pid")) as fh:
            pid = int(fh.read().strip())
    except Exception:
        pid = None
    check(pid is not None and alive(pid), "role %s pid %r not alive" % (role, pid))
    check(listening("127.0.0.1", port), "role %s port %d not listening" % (role, port))

# ------------------------------------------------------------- hidden configs
HIDDEN = "/tests/hidden"
cases = sorted(d for d in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, d))) if os.path.isdir(HIDDEN) else []
check(bool(cases), "no hidden configuration cases present")

for case in cases:
    base = os.path.join(HIDDEN, case)
    if not (os.path.isfile(os.path.join(base, "core.properties"))
            and os.path.isfile(os.path.join(base, "site.properties"))):
        failures.append("hidden case %s missing config files" % case)
        continue
    try:
        with open(os.path.join(base, "expected.json")) as fh:
            exp = json.load(fh)
        exp_port = int(exp["port"])
        must_boot = bool(exp["boot"])
    except Exception as exc:
        failures.append("hidden case %s: unreadable expected.json: %r" % (case, exc))
        continue

    run_dir_h = tempfile.mkdtemp(prefix="kelp_run_")
    env = dict(os.environ)
    env["KELP_CONF_DIR"] = base
    env["KELP_RUN_DIR"] = run_dir_h
    try:
        r = subprocess.run(["bash", START], capture_output=True, text=True,
                           timeout=120, env=env)
        if must_boot:
            check(r.returncode == 0, "[%s] boot rc=%s stderr=%s"
                  % (case, r.returncode, (r.stderr or "")[-300:]))
            check("KELP_CLUSTER_UP" in (r.stdout or ""),
                  "[%s] no KELP_CLUSTER_UP banner" % case)
            check(listening("127.0.0.1", exp_port),
                  "[%s] namenode port %d not listening" % (case, exp_port))
            check(listening("127.0.0.1", exp_port + 1),
                  "[%s] datanode port %d not listening" % (case, exp_port + 1))
            for role in ("namenode", "datanode"):
                check(os.path.isfile(os.path.join(run_dir_h, role + ".ready")),
                      "[%s] no ready marker for %s" % (case, role))
        else:
            check(r.returncode != 0,
                  "[%s] broken config must make start_cluster.sh exit "
                  "non-zero (rc=0, stdout=%r)" % (case, (r.stdout or "")[:120]))
    except subprocess.TimeoutExpired:
        if must_boot:
            failures.append("[%s] boot timed out" % case)
    finally:
        subprocess.run(["pkill", "-f", "kelp_daemon.py"], capture_output=True)
        time.sleep(0.3)
        shutil.rmtree(run_dir_h, ignore_errors=True)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY
rc=$?

pkill -f "kelp_daemon.py" 2>/dev/null || true
[ "$rc" -eq 0 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
