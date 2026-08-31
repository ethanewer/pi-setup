#!/bin/bash
# Real oracle for brass-dunlin: write the monitor.py program and the rule set,
# then RUN the program with defaults on the visible telemetry to produce
# /app/alert.json and /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/monitor.py"
RULES="/app/rules.json"

cat > "$SOLVER" <<'PY'
import datetime
import json
import re
import sys

LINE_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) device=(\S+) "
    r"metric=([A-Za-z0-9_]+) value=(-?\d+(?:\.\d+)?)$"
)
DEFAULT_RULES = "/app/rules.json"
DEFAULT_LOGS = ["/app/telemetry/edge-1.log", "/app/telemetry/edge-2.log"]


def load_rules(path):
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
    kept = []
    for r in rules:
        if not isinstance(r, dict):
            continue
        rid = r.get("id")
        if not isinstance(rid, str) or rid == "":
            continue
        metric = r.get("metric")
        metric = metric if isinstance(metric, str) else None
        mx = r.get("max")
        if isinstance(mx, bool) or not isinstance(mx, (int, float)):
            mx = None
        thr = r.get("threshold")
        thr = thr if isinstance(thr, int) and not isinstance(thr, bool) else 0
        sev = r.get("severity")
        sev = sev if isinstance(sev, str) else "info"
        kept.append({"id": rid, "metric": metric, "max": mx,
                     "threshold": thr, "severity": sev})
    return kept


def main():
    argv = sys.argv[1:]
    rules_path = argv[0] if argv else DEFAULT_RULES
    logs = argv[1:] if len(argv) > 1 else DEFAULT_LOGS
    rules = load_rules(rules_path)

    events = []
    matches = {id(r): 0 for r in rules}
    rule_ips = {id(r): [] for r in rules}
    for log_path in logs:
        try:
            with open(log_path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for raw in lines:
            line = raw.rstrip("\n")
            m = LINE_RE.match(line)
            if not m:
                continue
            device = m.group(2)
            metric = m.group(3)
            value = float(m.group(4))
            for r in rules:
                if r["metric"] is None or r["max"] is None:
                    continue
                if r["metric"] != metric or not (value > r["max"]):
                    continue
                matches[id(r)] += 1
                rule_ips[id(r)].append(device)
                events.append({
                    "rule": r["id"],
                    "device": device,
                    "value": value,
                    "line": line,
                })

    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")

    alerts = []
    for r in rules:
        n = matches[id(r)]
        if n >= r["threshold"]:
            alerts.append({
                "id": r["id"],
                "severity": r["severity"],
                "matches": n,
                "ips": sorted(set(rule_ips[id(r)])),
            })

    statistics = {}
    for r in rules:
        n = matches[id(r)]
        statistics[r["id"]] = {
            "id": r["id"],
            "metric": r["metric"],
            "max": r["max"],
            "threshold": r["threshold"],
            "severity": r["severity"],
            "matches": n,
            "unique_ips": len(set(rule_ips[id(r)])),
            "ips": sorted(set(rule_ips[id(r)])),
        }

    with open("/app/alert.json", "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "alerts": alerts}, fh, indent=2)
    with open("/app/report.json", "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "events": events,
                   "statistics": statistics}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

cat > "$RULES" <<'JSON'
{
  "rules": [
    { "id": "cpu_sizzle", "metric": "cpu_temp", "max": 85.0, "threshold": 3, "severity": "critical" },
    { "id": "mem_pressure", "metric": "mem_pct", "max": 92.0, "threshold": 2, "severity": "high" },
    { "id": "disk_hothead", "metric": "disk_temp", "max": 68.0, "threshold": 1, "severity": "medium" },
    { "id": "link_flap", "metric": "link_errors", "max": 50.0, "threshold": 5, "severity": "high" },
    { "id": "fan_wail", "metric": "fan_noise", "max": 62.0, "threshold": 9, "severity": "low" }
  ]
}
JSON

# Run the produced program with defaults on the visible telemetry.
python3 "$SOLVER"

echo "solve.sh done -> $SOLVER, $RULES, /app/alert.json, /app/report.json"
ls -l "$SOLVER" "$RULES" /app/alert.json /app/report.json
