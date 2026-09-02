#!/bin/bash
# Oracle for topaz-vane: write the triage.py program, author rules.json, then
# RUN the program with no arguments on the visible logs to produce
# /app/alert.json and /app/report.json. Never reads /tests.
set -eu

PROG="/app/triage.py"
RULES="/app/rules.json"

mkdir -p /app/logs

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$PROG" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

DEFAULT_RULES = "/app/rules.json"
DEFAULT_LOGS = ["/app/logs/gateway.log", "/app/logs/dns.log"]
ALERT_OUT = "/app/alert.json"
REPORT_OUT = "/app/report.json"


def load_rules(path):
    """Return a normalized list of rules; malformed input yields zero rules."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return []
    if not isinstance(data, dict):
        return []
    rules = data.get("rules")
    if not isinstance(rules, list):
        return []
    out = []
    for entry in rules:
        if not isinstance(entry, dict):
            continue
        rid = entry.get("id")
        kw = entry.get("keyword")
        if not isinstance(kw, str):
            kw = None  # matches nothing
        thr = entry.get("threshold", 0)
        if isinstance(thr, bool) or not isinstance(thr, int):
            thr = 0
        sev = entry.get("severity", "info")
        if not isinstance(sev, str):
            sev = "info"
        out.append({"id": rid, "keyword": kw, "threshold": thr, "severity": sev})
    return out


def scan(rules, logs):
    events = []
    stats = {}
    for rule in rules:
        stats[rule["id"]] = {"matches": 0, "unique_ips": 0, "ips": set()}
    for log_path in logs:
        try:
            with open(log_path, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        for line in lines:
            tokens = line.split()
            for rule in rules:
                kw = rule["keyword"]
                if kw is None or kw not in tokens:
                    continue
                ip = None
                for tok in tokens:
                    if tok.startswith("from="):
                        rest = tok[len("from="):]
                        if ip is None and rest:
                            ip = rest
                        if rest:
                            stats[rule["id"]]["ips"].add(rest)
                stats[rule["id"]]["matches"] += 1
                events.append({"rule": rule["id"], "ip": ip, "line": line})
    for rid in stats:
        stats[rid]["ips"] = sorted(stats[rid]["ips"])
        stats[rid]["unique_ips"] = len(stats[rid]["ips"])
    return events, stats


def main():
    argv = sys.argv[1:]
    rules_path = argv[0] if argv else DEFAULT_RULES
    logs = argv[1:] if len(argv) > 1 else list(DEFAULT_LOGS)

    rules = load_rules(rules_path)
    events, stats = scan(rules, logs)

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    alerts = []
    for rule in rules:
        s = stats[rule["id"]]
        if s["matches"] >= rule["threshold"]:
            alerts.append({
                "id": rule["id"],
                "severity": rule["severity"],
                "matches": s["matches"],
                "ips": s["ips"],
            })
    alerts.sort(key=lambda a: a["id"])

    with open(ALERT_OUT, "w", encoding="utf-8") as fh:
        json.dump({"timestamp": ts, "alerts": alerts}, fh, indent=2)
        fh.write("\n")
    with open(REPORT_OUT, "w", encoding="utf-8") as fh:
        json.dump({"timestamp": ts, "events": events, "statistics": stats},
                  fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$PROG"

# ---- 2. Author the scenario rule set.
cat > "$RULES" <<'JSON'
{
  "rules": [
    { "id": "port_probe", "keyword": "port_probe", "threshold": 3, "severity": "high" },
    { "id": "dns_tunnel", "keyword": "dns_tunnel", "threshold": 2, "severity": "medium" },
    { "id": "cred_stuffing", "keyword": "cred_stuffing", "threshold": 2, "severity": "high" },
    { "id": "beacon_1s", "keyword": "beacon_1s", "threshold": 4, "severity": "medium" },
    { "id": "noisy_scan", "keyword": "noisy_scan", "threshold": 50, "severity": "info" }
  ]
}
JSON

# ---- 3. Run the produced program with no arguments on the visible logs.
python3 "$PROG"

echo "solve.sh done -> $PROG, $RULES, /app/alert.json, /app/report.json"
ls -l "$PROG" "$RULES" /app/alert.json /app/report.json
