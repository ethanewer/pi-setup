#!/usr/bin/env python3
"""Independent verifier for the hollow-notch task (executes-deliverable).

Provisioner /app/setup.sh is executed against the default site and against
every hidden descriptor in /tests/hidden; the resulting system state is then
checked directly: three JVM daemons live, the RPC /status report is healthy,
name resolution is restored and persisted on disk, and the list announcement
lands in the local subscriber mailboxes. A malformed descriptor must abort
cleanly with no side effects.

Prints PASS/FAIL per check; exit 0 (=REWARD 1) only when every check holds.
"""
import json
import os
import re
import socket
import subprocess
import sys

FAILURES = []

MARK_DOMAIN = "hollow.farm"
MARKER = "PALISADE-RING-4421"
ANNOUNCE = "palisade-announce"
SUBSCRIBERS = ["sable", "rona", "trio"]
DEFAULT_HOST = "palisade-core.hollow.farm"


def check(name, cond, detail=""):
    if not cond:
        FAILURES.append(name)
    print(("PASS " if cond else "FAIL ") + name + ("  " + detail if detail else ""))


def run_setup(conf=None, timeout=180):
    cmd = ["bash", "/app/setup.sh"]
    if conf:
        cmd.append(conf)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def daemon_count():
    out = subprocess.run(
        ["bash", "-c", "pgrep -cf '^java -jar /app/palisade/palisade.jar' || true"],
        capture_output=True, text=True).stdout.strip()
    try:
        return int(out)
    except ValueError:
        return 0


def fetch_status(port):
    try:
        with socket.create_connection(("127.0.0.1", int(port)), timeout=3) as s:
            s.sendall(b"GET /status\n")
            s.shutdown(socket.SHUT_WR)
            data = b""
            while True:
                b = s.recv(4096)
                if not b:
                    break
                data += b
            return data.decode(errors="replace")
    except OSError:
        return None


def status_json(port):
    raw = fetch_status(port)
    if not raw:
        return None
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None


def sh(cmd):
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True).stdout


def getent(host):
    return sh("getent hosts '%s' || true" % host).strip()


def readfile(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def healthy_report(rpt):
    return (bool(rpt) and rpt.get("online") is True
            and len(rpt.get("nodes", [])) == 3
            and all(n.get("online") for n in rpt.get("nodes", [])))


# ---------------- visible case: default core site ------------------------------
print("== visible: default core site ==")
if not os.path.exists("/app/setup.sh") or not os.path.exists("/app/status.json"):
    check("deliverables /app/setup.sh and /app/status.json exist", False,
          "pristine image has no deliverables")
    print("REWARD=0")
    sys.exit(1)

p = run_setup()
check("default setup.sh exits 0", p.returncode == 0,
      "rc=%d %s" % (p.returncode, (p.stderr or "")[-300:]))

check("three JVM daemon processes live", daemon_count() == 3,
      "count=%d" % daemon_count())

rpt = status_json(26100)
check("primary RPC port 26100 serves a healthy live-cluster report",
      healthy_report(rpt),
      json.dumps(rpt)[:220] if rpt else "no report")

try:
    st = json.loads(readfile("/app/status.json"))
except Exception:
    st = {}
check("/app/status.json parses", bool(st))
check("status.json host == default site", st.get("host") == DEFAULT_HOST,
      "host=%r" % st.get("host"))
check("status.json online + 3 nodes + capacity",
      healthy_report(st)
      and st.get("capacity") == 65536 * 3 * 1024 * 1024,
      "capacity=%r" % st.get("capacity"))

check("expected host resolves end-to-end (getent hosts)",
      "127.0.0.1" in getent(DEFAULT_HOST), getent(DEFAULT_HOST))
check("resolution fix persists in /etc/hosts", DEFAULT_HOST in readfile("/etc/hosts"))
check("name-switch restored (hosts: files dns)",
      bool(re.search(r"^hosts:.*files.*dns", readfile("/etc/nsswitch.conf"), re.M)))
check("fqdn persisted in /etc/hostname",
      readfile("/etc/hostname").strip() == DEFAULT_HOST)

aliases = readfile("/etc/aliases")
mm = re.search(r"^\s*palisade-announce\s*:\s*(.*)$", aliases, re.M)
members = mm.group(1) if mm else ""
check("list declared in canonical /etc/aliases",
      bool(mm) and all((u.strip() in members) for u in SUBSCRIBERS),
      "members=%r" % members)
mcf = readfile("/etc/postfix/main.cf")
check("postfix mydestination covers list domain",
      MARK_DOMAIN in mcf and "mydestination" in mcf
      and not re.search(r"(?m)^\s*relayhost\s*=\s*\\S", mcf))
for u in SUBSCRIBERS:
    check("subscriber mailbox /var/mail/%s holds the announcement" % u,
          MARKER in readfile("/var/mail/" + u))

# ---------------- hidden cases ------------------------------------------------
print("== hidden cases ==")
HIDDEN = [
    ("site-replica.conf", True, [36120, 36121, 36122], 16384, "palisade-replica.hollow.farm"),
    ("site-plum.conf",    True, [36200, 36201, 36202], 3072,  "plake.hollow.farm"),
    ("site-broken.conf",  False, None, None, None),
]
for fname, expect_ok, ports, cap_mb, host in HIDDEN:
    tag = "hidden:%s" % fname
    p = run_setup("/tests/hidden/" + fname)
    if expect_ok:
        check(tag + " exits 0", p.returncode == 0,
              "rc=%d %s" % (p.returncode, (p.stderr or "")[-200:]))
        rpt = status_json(ports[0])
        check(tag + " new RPC port serves healthy report for host " + host,
              healthy_report(rpt) and rpt.get("host") == host,
              json.dumps(rpt)[:220] if rpt else "no report")
        check(tag + " new site resolves + persists",
              "127.0.0.1" in getent(host) and host in readfile("/etc/hosts"))
        check(tag + " three JVM daemons for the new site", daemon_count() == 3)
    else:
        check(tag + " malformed descriptor aborts cleanly",
              p.returncode != 0, "rc=%d" % p.returncode)
        check(tag + " broke input leaves a healthy status.json untouched",
              "hollow" in readfile("/app/status.json")
              and '"online":true' in readfile("/app/status.json"))

print("")
if FAILURES:
    print("REWARD=0  (%d failed)" % len(FAILURES))
    for f in FAILURES:
        print("  - " + f)
    sys.exit(1)
print("REWARD=1")
sys.exit(0)