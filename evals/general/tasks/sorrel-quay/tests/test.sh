#!/bin/sh
# Verifier for sorrel-quay (executes-deliverable).
# 1) Textual/XML check: /app/conf/core-site.xml and /app/conf/hdfs-site.xml must
#    carry exactly the designated single-node cluster values.
# 2) Live cluster check: both role daemons are started against the agent's site
#    files and must bind the designated endpoints (rpc 9000, web UI 9870,
#    datanode 9866).
# 3) Hidden probes: each hidden probe is executed against the live cluster and
#    its stdout compared to ground truth.
# Writes reward to /logs/verifier/reward.txt.
mkdir -p /logs/verifier
python3 - <<'PYEOF'
import os
import socket
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

failures = []
HALL = "/tests/hidden"
CORE = "/app/conf/core-site.xml"
HDFS = "/app/conf/hdfs-site.xml"


def check(cond, msg):
    if not cond:
        failures.append(msg)


def parse_site(path):
    if not os.path.isfile(path):
        check(False, "missing site file %s" % path)
        return None
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        check(False, "%s is not valid XML: %r" % (path, exc))
        return None
    props = {}
    for prop in root.findall("property"):
        name = (prop.findtext("name") or "").strip()
        value = (prop.findtext("value") or "").strip()
        check(name != "", "%s has a property with empty name" % path)
        check(name not in props, "%s duplicates property %s" % (path, name))
        props[name] = value
    return props


def port_listens(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        try:
            s.close()
        except Exception:
            pass


def wait_file(path, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if os.path.isfile(path):
            return True
        time.sleep(0.25)
    return False


# ------------------------------------------------- textual/XML config checks
DESIGNATED = {
    CORE: {
        "fs.defaultFS": "hdfs://127.0.0.1:9000",
        "hadoop.tmp.dir": "/app/data/tmp",
    },
    HDFS: {
        "dfs.replication": "1",
        "dfs.namenode.http-address": "127.0.0.1:9870",
        "dfs.datanode.address": "127.0.0.1:9866",
        "dfs.namenode.name.dir": "/app/data/namenode",
        "dfs.datanode.data.dir": "/app/data/datanode",
    },
}
all_props = {}
for path, expected in DESIGNATED.items():
    props = parse_site(path)
    if props is None:
        continue
    all_props.update(props)
    for key, want in expected.items():
        got = props.get(key)
        check(got == want,
              "site %s property %s = %r, designated %r" % (os.path.basename(path), key, got, want))

# ------------------------------------------------------- live cluster checks
procs = []
if not failures:
    os.makedirs("/app/run", exist_ok=True)
    for marker in ("namenode.ready", "datanode.ready"):
        try:
            os.remove(os.path.join("/app/run", marker))
        except OSError:
            pass
    for role in ("namenode", "datanode"):
        p = subprocess.Popen(
            [sys.executable, "/app/sbin/name-daemon.py", role],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        procs.append((role, p))
    ok = True
    for marker in ("namenode.ready", "datanode.ready"):
        if not wait_file(os.path.join("/app/run", marker), 30):
            failures.append("role did not come up (missing %s); site config rejected" % marker)
            ok = False
    time.sleep(0.5)
    if ok:
        for role, p in procs:
            if p.poll() is not None:
                err = b""
                try:
                    err = (p.stderr.read() or b"")[-300:]
                except Exception:
                    pass
                check(False, "role %s exited early (config defect): %s" % (role, err))
        for port, label in ((9000, "namenode rpc"), (9870, "namenode web UI"),
                            (9866, "datanode")):
            check(port_listens(port), "designated endpoint %s (%d) not listening"
                  % (label, port))

# ------------------------------------------------------------- hidden probes
if os.path.isdir(HALL):
    cases = sorted(d for d in os.listdir(HALL)
                   if os.path.isfile(os.path.join(HALL, d, "probe.py"))
                   and os.path.isfile(os.path.join(HALL, d, "expected.txt")))
    if not cases:
        failures.append("no hidden probe cases present")
    for case in cases:
        base = os.path.join(HALL, case)
        try:
            r = subprocess.run([sys.executable, os.path.join(base, "probe.py"), "/app/conf"],
                               capture_output=True, text=True, timeout=60)
        except Exception as exc:
            failures.append("probe %s crashed: %r" % (case, exc))
            continue
        if r.returncode != 0:
            failures.append("probe %s failed rc=%s: %s" % (case, r.returncode, (r.stderr or "")[-300:]))
            continue
        got = [ln for ln in r.stdout.splitlines()]
        with open(os.path.join(base, "expected.txt")) as fh:
            want = [ln.rstrip("\n") for ln in fh]
        if got != want:
            failures.append("probe %s output %r != expected %r" % (case, got, want))
else:
    failures.append("no /tests/hidden")

# ------------------------------------------------------------------- cleanup
for role, p in procs:
    try:
        p.terminate()
    except Exception:
        pass
for role, p in procs:
    try:
        p.wait(timeout=10)
    except Exception:
        pass

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
