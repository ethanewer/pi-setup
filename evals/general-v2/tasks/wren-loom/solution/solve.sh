#!/bin/bash
# Real oracle for wren-loom: write the provisioning script, then RUN it on the
# visible spec fixture to produce /app/lists_report.json. Never reads /tests.
set -eu

PROVISION="/app/provision.sh"
REPORT="/app/lists_report.json"

# ---- 1. Write the deliverable script (this IS the work, not a canned answer).
cat > "$PROVISION" <<'SH'
#!/bin/bash
# Provision the loopd mailing-list configuration at the canonical path
# /etc/loopd/lists.conf from a spec CSV, then reload the live daemon.
set -eu
SPEC="${1:-/app/spec/lists.csv}"
python3 - "$SPEC" <<'PY'
import json
import os
import signal
import socket
import sys
import time

spec_path = sys.argv[1]
CONFIG_DIR = "/etc/loopd"
CONFIG_PATH = os.path.join(CONFIG_DIR, "lists.conf")
PORT = 7871
PIDFILE = "/run/loopd.pid"

# ---- parse the spec CSV (header: name,address,members,enabled) -------------
by_name = {}
with open(spec_path, encoding="utf-8") as fh:
    header = fh.readline().rstrip("\n")
    if [c.strip() for c in header.split(",")[:4]] != ["name", "address", "members", "enabled"]:
        raise SystemExit("provision: unexpected spec header: %r" % header)
    for line in fh:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split(",")
        name = parts[0].strip()
        address = parts[1].strip() if len(parts) > 1 else ""
        members_raw = parts[2].strip() if len(parts) > 2 else ""
        enabled = parts[3].strip().lower() == "true" if len(parts) > 3 else False
        members = [m.strip() for m in members_raw.split(";") if m.strip()]
        by_name[name] = {"address": address, "members": members, "enabled": enabled}

# ---- write the canonical config --------------------------------------------
os.makedirs(CONFIG_DIR, exist_ok=True)
lines = ["# loopd mailing-list configuration (provisioned)"]
for name, entry in by_name.items():
    lines.append("")
    lines.append("[%s]" % name)
    lines.append("address = %s" % entry["address"])
    lines.append("members = %s" % ", ".join(entry["members"]))
    lines.append("enabled = %s" % ("true" if entry["enabled"] else "false"))
with open(CONFIG_PATH, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")

# ---- reload the running daemon ----------------------------------------------
with open(PIDFILE) as fh:
    os.kill(int(fh.read().strip()), signal.SIGHUP)
time.sleep(0.5)


def query(cmd):
    s = socket.create_connection(("127.0.0.1", PORT), 5)
    try:
        s.sendall((cmd + "\n").encode("utf-8"))
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        return buf.decode("utf-8").strip()
    finally:
        s.close()


listing = query("LISTS")
enabled = [] if listing in ("NONE", "UNKNOWN", "ERR", "") else listing.split(",")

report = {
    "daemon_port": PORT,
    "config_path": CONFIG_PATH,
    "enabled": enabled,
    "lists": {},
}
for name in enabled:
    members_raw = query("MEMBERS %s" % name)
    members = [] if members_raw == "" else members_raw.split(",")
    count = int(query("COUNT %s" % name))
    report["lists"][name] = {
        "address": by_name[name]["address"],
        "members": members,
        "count": count,
    }

with open("/app/lists_report.json", "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
PY
SH
chmod +x "$PROVISION"

# 2. Run the produced script on the visible spec fixture to generate the
#    second deliverable.
bash "$PROVISION" /app/spec/lists.csv

echo "solve.sh done -> $PROVISION and $REPORT"
ls -l "$PROVISION" "$REPORT"
