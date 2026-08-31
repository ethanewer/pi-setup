#!/bin/bash
# Oracle for juniper-hollow: write the triage.py program, then RUN it on the
# visible fixtures to produce /app/alert.json and /app/report.json.
# Never reads /tests.
set -eu

SOLVER="/app/triage.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

IP_RE = re.compile(r"ip=(\d{1,3}(?:\.\d{1,3}){3})")


def load_rules(path):
    """Return the list of accepted rule dicts (normalized)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            root = json.load(fh)
    except Exception:
        return []
    if not isinstance(root, dict):
        return []
    raw = root.get("rules")
    if not isinstance(raw, list):
        return []
    rules = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        rid = item.get("id")
        if not isinstance(rid, str):
            continue
        raw_pattern = item.get("pattern")
        # A missing/non-string pattern is reported as "" but matches nothing.
        pattern = raw_pattern if isinstance(raw_pattern, str) else ""
        threshold = item.get("threshold")
        if not isinstance(threshold, int) or isinstance(threshold, bool):
            threshold = 1
        severity = item.get("severity")
        severity = severity if isinstance(severity, str) else "medium"
        compiled = None
        if isinstance(raw_pattern, str):
            try:
                compiled = re.compile(raw_pattern)
            except re.error:
                compiled = None
        rules.append({
            "id": rid,
            "pattern": pattern,
            "threshold": threshold,
            "severity": severity,
            "compiled": compiled,
        })
    return rules


def main():
    rules_path, out_dir = sys.argv[1], sys.argv[2]
    log_paths = sys.argv[3:]
    for p in log_paths:
        if not os.path.isfile(p):
            print("missing log file: %s" % p, file=sys.stderr)
            sys.exit(2)

    rules = load_rules(rules_path)

    matches = {r["id"]: [] for r in rules}  # rule id -> list of (ip, line)
    for lp in log_paths:
        with open(lp, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                for r in rules:
                    if r["compiled"] is None:
                        continue
                    if r["compiled"].search(line):
                        m = IP_RE.search(line)
                        ip = m.group(1) if m else None
                        matches[r["id"]].append((ip, line))

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    statistics = {}
    for r in rules:
        ips = sorted({ip for ip, _ in matches[r["id"]] if ip is not None})
        statistics[r["id"]] = {
            "id": r["id"],
            "pattern": r["pattern"],
            "threshold": r["threshold"],
            "severity": r["severity"],
            "matches": len(matches[r["id"]]),
            "ips": ips,
        }

    alerts = []
    for r in sorted(rules, key=lambda r: r["id"]):
        stat = statistics[r["id"]]
        if stat["matches"] >= r["threshold"]:
            alerts.append({
                "id": r["id"],
                "severity": r["severity"],
                "matches": stat["matches"],
                "ips": stat["ips"],
            })

    events = []
    for lp in log_paths:
        with open(lp, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                for r in rules:
                    if r["compiled"] is None:
                        continue
                    if r["compiled"].search(line):
                        m = IP_RE.search(line)
                        events.append({
                            "rule": r["id"],
                            "ip": m.group(1) if m else None,
                            "line": line,
                        })

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "alert.json"), "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "alerts": alerts}, fh, indent=2)
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "events": events,
                   "statistics": statistics}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the bundle.
python3 "$SOLVER" /app/rules.json /app /app/edge/gateway.log /app/edge/dns.log

echo "solve.sh done -> $SOLVER, /app/alert.json, /app/report.json"
ls -l "$SOLVER" /app/alert.json /app/report.json
