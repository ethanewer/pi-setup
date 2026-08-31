#!/bin/bash
# Oracle for flint-signal: write the scanner and the pinned rule set, then RUN
# the scanner with defaults to produce /app/alert.json and /app/report.json.
# Never reads /tests.
set -eu

SCANNER="/app/pipeline_scan.py"
RULES="/app/rules.json"
ALERT="/app/alert.json"
REPORT="/app/report.json"

# ---- 1. Write the pinned rule set (a deliverable).
cat > "$RULES" <<'JSON'
{
  "rules": [
    {"id": "secret_exfil", "pattern": "credential", "threshold": 3, "severity": "high"},
    {"id": "artifact_tamper", "pattern": "checksum mismatch", "threshold": 2, "severity": "high"},
    {"id": "fork_bomb", "pattern": "process spike", "threshold": 1, "severity": "medium"},
    {"id": "stale_cache", "pattern": "cache miss", "threshold": 2, "severity": "low"},
    {"id": "telemetry_ping", "pattern": "heartbeat", "threshold": 10, "severity": "notice"}
  ]
}
JSON

# ---- 2. Write the deliverable scanner program (this IS the work).
cat > "$SCANNER" <<'PY'
import argparse
import json
import re
import sys
from datetime import datetime, timezone

IP_RE = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b")
DEFAULT_RULES = "/app/rules.json"
DEFAULT_LOGS = ["/app/logs/build.log", "/app/logs/deploy.log"]


def load_rules(path):
    """Load rules defensively; any malformation yields fewer/no rules."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except Exception:
        return []
    if not isinstance(obj, dict):
        return []
    rules = obj.get("rules")
    if not isinstance(rules, list):
        return []
    parsed = []
    for item in rules:
        if not isinstance(item, dict):
            continue
        rid = item.get("id")
        pattern = item.get("pattern")
        threshold = item.get("threshold")
        severity = item.get("severity")
        if not isinstance(rid, str):
            rid = ""
        compiled = None
        if isinstance(pattern, str):
            try:
                compiled = re.compile(pattern)
            except re.error:
                compiled = None
        if isinstance(threshold, bool) or not isinstance(threshold, int):
            threshold = 0
        if not isinstance(severity, str):
            severity = "info"
        parsed.append(
            {"id": rid, "threshold": threshold, "severity": severity, "re": compiled}
        )
    return parsed


def main():
    ap = argparse.ArgumentParser(description="Helix CI rule-driven log scanner")
    ap.add_argument("-r", "--rules", default=DEFAULT_RULES)
    ap.add_argument("logs", nargs="*")
    args = ap.parse_args()
    logs = args.logs if args.logs else list(DEFAULT_LOGS)

    alerts = []
    statistics = {}
    events = []
    for rule in load_rules(args.rules):
        matches = 0
        ips = set()
        rx = rule["re"]
        for log_path in logs:
            try:
                fh = open(log_path, "r", encoding="utf-8", errors="replace")
            except OSError:
                continue
            with fh:
                for raw in fh:
                    line = raw.rstrip("\r\n")
                    if rx is None or not rx.search(line):
                        continue
                    matches += 1
                    found = IP_RE.findall(line)
                    ips.update(found)
                    events.append(
                        {
                            "rule": rule["id"],
                            "ip": found[0] if found else None,
                            "line": line,
                        }
                    )
        statistics[rule["id"]] = {"matches": matches, "unique_ips": len(ips)}
        if matches >= rule["threshold"]:
            alerts.append(
                {
                    "id": rule["id"],
                    "severity": rule["severity"],
                    "matches": matches,
                    "ips": sorted(ips),
                }
            )

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open("/app/alert.json", "w", encoding="utf-8") as fh:
        json.dump({"timestamp": ts, "alerts": alerts}, fh, indent=2)
    with open("/app/report.json", "w", encoding="utf-8") as fh:
        json.dump({"timestamp": ts, "statistics": statistics, "events": events}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SCANNER"

# ---- 3. Run the produced scanner on the visible fixtures (default paths).
python3 "$SCANNER"

echo "solve.sh done -> $SCANNER, $RULES, $ALERT, $REPORT"
ls -l "$SCANNER" "$RULES" "$ALERT" "$REPORT"
