#!/usr/bin/env bash
# Verifier for tasks/brume-delta (executes-deliverable).
# Checks the two site-config deliverables textually (valid XML, exact
# required property values, complementary namenode address), then EXECUTES
# them: launches both ShoreDFS roles with the agent's config, requires the
# ready markers, the recorded datanode registration address, the role
# banners, and runs every hidden client-operation sequence against a freshly
# started cluster. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never
# runs solve.sh.
set -u

mkdir -p /logs/verifier

python3 - <<'PYEOF'
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

CORE = "/app/conf/core-site.xml"
HDFS = "/app/conf/hdfs-site.xml"
RUN_DIR = "/app/run"
failures = []

REQUIRED = {
    CORE: {"fs.defaultFS": "hdfs://127.0.0.1:19310"},
    HDFS: {
        "dfs.namenode.rpc-address": "127.0.0.1:19310",
        "dfs.datanode.address": "127.0.0.1:19311",
        "dfs.replication": "1",
        "dfs.permissions.enabled": "false",
        "dfs.namenode.name.dir": "/app/data/namenode",
        "dfs.datanode.data.dir": "/app/data/datanode",
    },
}


def check(cond, msg):
    if not cond:
        failures.append(msg)


def read_props(path, label):
    if not os.path.isfile(path):
        check(False, "missing deliverable %s" % path)
        return None
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        check(False, "[%s] invalid XML: %r" % (label, exc))
        return None
    props = {}
    for p in root.iter("property"):
        name = p.findtext("name")
        if not name:
            check(False, "[%s] property without <name>" % label)
            continue
        props[name.strip()] = (p.findtext("value") or "").strip()
    return props


props = {}
for path in (CORE, HDFS):
    got = read_props(path, path)
    if got is not None:
        props[path] = got
        for key, want in REQUIRED[path].items():
            check(got.get(key) == want,
                  "%s: %s = %r (required %r)" % (path, key, got.get(key), want))

fs = props.get(CORE, {}).get("fs.defaultFS", "")
m = re.match(r"^hdfs://([A-Za-z0-9._-]+):(\d+)$", fs)
fs_addr = "%s:%s" % (m.group(1), m.group(2)) if m else None
rpc = props.get(HDFS, {}).get("dfs.namenode.rpc-address", "")
check(m is not None, "fs.defaultFS is not hdfs://HOST:PORT (%r)" % fs)
check(bool(rpc) and fs_addr is not None and rpc == fs_addr,
      "dfs.namenode.rpc-address %r must match fs.defaultFS %r" % (rpc, fs_addr))

procs = {}


def stop_cluster():
    subprocess.run(["pkill", "-f", "dfsnode.py"], capture_output=True)
    for name in ("nn", "dn"):
        p = procs.pop(name, None)
        if p is not None:
            try:
                p.terminate()
                p.wait(timeout=10)
            except Exception:
                try:
                    p.kill()
                except Exception:
                    pass
    time.sleep(0.4)


def fresh_state():
    for f in ("namenode.ready", "datanode.ready"):
        try:
            os.remove(os.path.join(RUN_DIR, f))
        except OSError:
            pass
    shutil.rmtree("/app/data/namenode", ignore_errors=True)
    shutil.rmtree("/app/data/datanode", ignore_errors=True)


def start_cluster(label):
    """Start both roles with the agent's config; return list of failures."""
    fresh_state()
    logs = {}
    for role, key in (("namenode", "nn"), ("datanode", "dn")):
        logf = open("/tmp/shoredfs_%s_%s.log" % (role, label), "wb")
        procs[key] = subprocess.Popen(
            ["python3", "/opt/shoredfs/dfsnode.py", role],
            stdout=logf, stderr=subprocess.STDOUT)
        logs[key] = logf
    # namenode ready
    for _ in range(120):
        if procs["nn"].poll() is not None:
            break
        if os.path.isfile(os.path.join(RUN_DIR, "namenode.ready")):
            break
        time.sleep(0.5)
    if not os.path.isfile(os.path.join(RUN_DIR, "namenode.ready")):
        return "[%s] namenode never became ready (config may be invalid)" % label
    # datanode ready (only after registering with the namenode)
    for _ in range(120):
        if procs["dn"].poll() is not None:
            break
        if os.path.isfile(os.path.join(RUN_DIR, "datanode.ready")):
            break
        time.sleep(0.5)
    marker = os.path.join(RUN_DIR, "datanode.ready")
    if not os.path.isfile(marker):
        return "[%s] datanode never registered with the namenode" % label
    try:
        with open(marker) as fh:
            content = fh.read()
        got = re.search(r"namenode=(\S+)", content)
        check(got is not None and got.group(1) == fs_addr,
              "[%s] datanode registered at %r (expected %s)" % (label, got.group(1) if got else None, fs_addr))
    except Exception as exc:
        check(False, "[%s] datanode.ready unreadable: %r" % (label, exc))
    # banners on the designated ports
    if fs_addr:
        mh = re.match(r"^([A-Za-z0-9._-]+):(\d+)$", fs_addr)
        try:
            s = socket.create_connection((mh.group(1), int(mh.group(2))), 5)
            banner = s.recv(64)
            s.close()
            check(banner.startswith(b"SHOREDFS-NN READY"),
                  "[%s] namenode banner wrong: %r" % (label, banner))
        except Exception as exc:
            check(False, "[%s] namenode banner unreachable: %r" % (label, exc))
    dn_addr = props.get(HDFS, {}).get("dfs.datanode.address", "")
    md = re.match(r"^([A-Za-z0-9._-]+):(\d+)$", dn_addr)
    if md:
        try:
            s = socket.create_connection((md.group(1), int(md.group(2))), 5)
            banner = s.recv(64)
            s.close()
            check(banner.startswith(b"SHOREDFS-DN READY"),
                  "[%s] datanode banner wrong: %r" % (label, banner))
        except Exception as exc:
            check(False, "[%s] datanode banner unreachable: %r" % (label, exc))
    return None


# ------------------------------------------------------ hidden client ops
hidden_dir = "/tests/hidden"
cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
if not cases:
    check(False, "no hidden cases present")
for c in cases:
    base = os.path.join(hidden_dir, c)
    ops = os.path.join(base, "ops.txt")
    expf = os.path.join(base, "expected.json")
    if not (os.path.isfile(ops) and os.path.isfile(expf)):
        check(False, "hidden case '%s' malformed (missing ops/expected)" % c)
        continue
    err = start_cluster(c)
    if err:
        check(False, err)
        stop_cluster()
        continue
    try:
        r = subprocess.run(
            ["python3", "/opt/shoredfs/dfsclient.py", "--config-dir", "/app/conf",
             "--ops", ops],
            capture_output=True, text=True, timeout=120)
        got = r.stdout.splitlines()
        with open(expf) as fh:
            want = json.load(fh)
        check(r.returncode == 0, "[%s] dfsclient rc=%s stderr=%s" % (c, r.returncode, (r.stderr or "")[-200:]))
        check(got == list(want), "[%s] client output mismatch: got %r want %r" % (c, got, want))
        # blocks must actually live in the configured datanode data dir
        # (one file per distinct successfully-written name)
        datadir = props.get(HDFS, {}).get("dfs.datanode.data.dir", "")
        names = set(ln.split()[1] for ln in got
                    if ln.startswith("PUT ") and ln.endswith(" OK"))
        if datadir and os.path.isdir(datadir):
            check(len(os.listdir(datadir)) >= len(names),
                  "[%s] datanode data dir has %d files, expected >= %d blocks"
                  % (c, len(os.listdir(datadir)), len(names)))
        else:
            check(False, "[%s] datanode data dir %r missing" % (c, datadir))
    except Exception as exc:
        check(False, "[%s] client run failed: %r" % (c, exc))
    stop_cluster()

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
