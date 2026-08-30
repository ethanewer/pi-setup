#!/bin/sh
# Verifier for tasks/brisk-grove (executes-deliverable).
#
# Exercises every deliverable objectively and independently:
#   * boots start.sh (idempotently) and confirms the three JVM daemon roles are
#     alive, the designated RPC port listens, the dependent gateway answers a
#     client with the readiness banner, and the site config carries the
#     designated address/port/complementary role bindings;
#   * resolves the NAMED slurm launcher from launcher.yaml without touching the
#     job submission fields;
#   * records the runner interpreter path in runner/settings.json and runs it;
#   * exposes four tool env vars to a fresh shell that sources the startup rc;
#     and
#   * re-runs monitor_gen.sh on the current cluster and each genuinely-
#     different hidden node scenario, verifying the exact header + node-count +
#     3-decimal fraction format and that counts reflect the rotated state.
# Writes reward to /logs/verifier/reward.txt.
mkdir -p /logs/verifier
python3 - <<'PYEOF'
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import xml.etree.ElementTree as ET

failures = []
HALL = "/tests/hidden"
STATE = "/opt/mdsl/state/nodes.json"
BANNER = b"MDS-GATEWAY-READY"


def check(cond, msg):
    if not cond:
        failures.append(msg)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def port(addr, port):
    """True if TCP connect to addr:port succeeds."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
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


def banner(addr, port):
    """Returns (accepted, banner_line_startswith_expected)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect((addr, port))
        data = s.recv(64)
        return True, data.startswith(BANNER)
    except Exception:
        return False, False
    finally:
        try:
            s.close()
        except Exception:
            pass


def validate_monitor(expect_total, expect_idle, label):
    try:
        with open("/app/monitor.log") as fh:
            lines = [ln.rstrip("\n") for ln in fh]
    except Exception as exc:
        check(False, "[%s] monitor.log unreadable: %r" % (label, exc))
        return
    headers = [ln for ln in lines if ln.startswith("# MDS CLUSTER MONITOR - ")]
    check(len(headers) == 1, "[%s] expected exactly 1 header, got %d" % (label, len(headers)))
    if len(headers) == 1:
        check(lines and lines[0] == headers[0], "[%s] header not first line" % label)
        ts = headers[0][len("# MDS CLUSTER MONITOR - "):]
        check(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", ts) is not None,
              "[%s] bad header timestamp %r" % (label, ts))
    check(len(lines) >= 4, "[%s] monitor.log short: %r" % (label, lines))
    got_total = lines[1] if len(lines) > 1 else None
    got_idle = lines[2] if len(lines) > 2 else None
    check(got_total == "Node total: %d" % expect_total,
          "[%s] Node total %r != %d" % (label, got_total, expect_total))
    check(got_idle == "Node idle: %d" % expect_idle,
          "[%s] Node idle %r != %d" % (label, got_idle, expect_idle))
    exp_frac = "0.000" if expect_total <= 0 else "%.3f" % (
        (expect_total - expect_idle) / expect_total)
    m = re.fullmatch(r"LoadFraction: (\d+\.\d{3})", lines[3] if len(lines) > 3 else "")
    check(m is not None, "[%s] LoadFraction malformed: %r" % (label, lines[3] if len(lines) > 3 else ""))
    if m:
        check(m.group(1) == exp_frac, "[%s] fraction %s != %s" % (label, m.group(1), exp_frac))


def current_state():
    with open(STATE) as fh:
        d = json.load(fh)
    return int(d.get("total", 0)), int(d.get("idle", 0))


# ---------------------------------------------------------------- deliverables
for path in ("/app/start.sh", "/app/monitor_gen.sh", "/app/monitor.log",
             "/app/config/core.xml", "/app/launcher.yaml",
             "/app/runner/settings.json", "/app/env.sh"):
    check(os.path.isfile(path), "missing deliverable %s" % path)
for p in ("/app/start.sh", "/app/monitor_gen.sh", "/app/env.sh"):
    check(os.access(p, os.X_OK), "not executable %s" % p)

# -------------------------------------------------------------------- boot it
r = run(["bash", "/app/start.sh"])
check(r.returncode == 0, "start.sh failed rc=%s: %s" % (r.returncode, (r.stderr or "")[-400:]))
check("MDS_CLUSTER_UP" in r.stdout, "start.sh did not print MDS_CLUSTER_UP")

try:
    root = ET.parse("/app/config/core.xml").getroot()
    props = {}
    for p in root.findall("property"):
        props[p.findtext("name")] = (p.findtext("value") or "").strip()
except Exception as exc:
    props = {}
    check(False, "core.xml invalid xml: %r" % exc)

check(props.get("mds.address") == "127.0.0.1",
      "designated address != 127.0.0.1 (%r)" % props.get("mds.address"))
check(props.get("mds.rpc.port") == "18021",
      "designated rpc port != 18021 (%r)" % props.get("mds.rpc.port"))
for k, v in {"mds.binding.primary": "namenode", "mds.binding.data": "datanode",
             "mds.binding.secondary": "journal-node"}.items():
    check(props.get(k) == v, "binding %s != %r (%r)" % (k, v, props.get(k)))
rpc_port = int(props.get("mds.rpc.port") or "0")
addr = props.get("mds.address") or "127.0.0.1"

# three JVM daemon roles alive and their role ports listening
for role, off in (("primary", 0), ("data", 1), ("secondary", 2)):
    check(os.path.isfile("/app/run/%s.ready" % role), "no ready marker for role %s" % role)
    pid = None
    try:
        pid = int(open("/app/run/%s.pid" % role).read().strip())
    except Exception:
        pid = None
    if pid is not None:
        alive = subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode == 0
        check(alive, "role %s pid %s not alive" % (role, pid))
    check(port(addr, rpc_port + off), "role %s port %d not listening" % (role, rpc_port + off))

# dependent gateway reachable by an independent client + the shipped client
accepted, banner_ok = banner(addr, rpc_port + 10)
check(accepted and banner_ok,
      "gateway port %d did not answer banner" % (rpc_port + 10))
cr = run(["python3", "/app/bin/client_check.py"])
check(cr.returncode == 0 and "gateway OK" in cr.stdout,
      "client_check on running server failed: %s" % (cr.stdout + cr.stderr))

# ------------------------------------------------------------ named launcher
lr = run(["/opt/mdsl/bin/mdsl-resolve", "/app/launcher.yaml", "slurm"])
check(lr.returncode == 0, "mdsl-resolve slurm failed: %s" % (lr.stdout + lr.stderr))
resolved = {}
for ln in lr.stdout.splitlines():
    if ln.startswith("TARGET "):
        resolved["TARGET"] = ln[len("TARGET "):].strip()
    elif "=" in ln:
        k, v = ln.split("=", 1)
        resolved[k] = v
check(resolved.get("TARGET") == "mdsl.launcher.SlurmLauncher",
      "launcher target wrong (%r)" % resolved.get("TARGET"))
for k, v in {"partition": "batch", "account": "mdsl", "cpus_per_task": "4"}.items():
    check(resolved.get(k) == v, "launcher param %s != %r (%r)" % (k, v, resolved.get(k)))
check(resolved.get("JOB_NAME") == "rank-pivot", "job.name must be unchanged (%r)" % resolved.get("JOB_NAME"))
check(resolved.get("JOB_NODES") == "2", "job.nodes must be unchanged (%r)" % resolved.get("JOB_NODES"))
sr = run(["/opt/mdsl/bin/mdsl-resolve", "/app/launcher.yaml"])
check(sr.returncode == 0 and "TARGET mdsl.launcher.SlurmLauncher" in sr.stdout,
      "launcher must be selectable by default selection field")

# ------------------------------------------------------------ interpreter path
interp = ""
try:
    with open("/app/runner/settings.json") as fh:
        settings = json.load(fh)
    interp = settings.get("interpreter") or ""
except Exception as exc:
    check(False, "settings.json unreadable: %r" % exc)
check(isinstance(interp, str) and interp.strip() and os.path.isabs(interp.strip()),
      "runner.interpreter missing or not an absolute path (%r)" % interp)
p = interp.strip()
check(os.path.isfile(p) and os.access(p, os.X_OK),
      "interpreter not an existing executable (%r)" % p)
if os.path.isfile(p) and os.access(p, os.X_OK):
    vr = run([p, "-c", "import sys;print(sys.version_info[0])"])
    check(vr.returncode == 0 and vr.stdout.strip() == "3",
          "interpreter not a python3 (%r)" % vr.stdout)

# --------------------------------------------------- env vars in a fresh shell
home = os.environ.get("HOME", "/root")
envcheck = run(["env", "-i", "HOME=%s" % home, "PATH=/usr/bin:/bin",
                "bash", "-ic",
                'printf "%s|%s|%s|%s" "$MDS_HOME" "$MDS_BIN" "$MDS_LAUNCHER" "$MDS_RPC_PORT"'])
check(envcheck.returncode == 0, "fresh-shell env check crashed: %s" % (envcheck.stdout + envcheck.stderr))
parts = envcheck.stdout.strip().split("|")
exp = ["/opt/mdsl", "/opt/mdsl/bin", "slurm", "18021"]
check(parts == exp, "fresh-shell env values wrong: %r != %r" % (parts, exp))

# --------------------------------------------------- monitoring log (current)
t, i = current_state()
run(["bash", "/app/monitor_gen.sh"])
validate_monitor(t, i, "current")

# --------------------------------------------------- monitoring: hidden nodes
hidden_dirs = []
if os.path.isdir(HALL):
    for d in sorted(os.listdir(HALL)):
        full = os.path.join(HALL, d)
        if os.path.isfile(os.path.join(full, "nodes.json")):
            hidden_dirs.append(full)
if not hidden_dirs:
    check(False, "no hidden node scenarios mounted")
else:
    for hd in hidden_dirs:
        # rotate in a genuinely different cluster state
        with open(os.path.join(hd, "nodes.json")) as fh:
            d = json.load(fh)
        ht, hi = int(d["total"]), int(d["idle"])
        shutil.copyfile(os.path.join(hd, "nodes.json"), STATE)
        rr = run(["bash", "/app/monitor_gen.sh"])
        check(rr.returncode == 0, "[%s] monitor_gen.sh rc=%s" % (os.path.basename(hd), rr.returncode))
        validate_monitor(ht, hi, os.path.basename(hd))

# ------------------------------------------------------------------- reward
if failures:
    print("FAILURES:")
    for msg in failures:
        print("  - " + msg)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF