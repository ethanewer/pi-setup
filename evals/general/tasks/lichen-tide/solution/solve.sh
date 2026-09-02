#!/bin/bash
# Oracle for lichen-tide: write the triage.py program, then RUN it on the
# visible fixtures to produce /app/alert.json and /app/report.json.
# Never reads /tests.
set -eu

SOLVER="/app/triage.py"
ALERT="/app/alert.json"
REPORT="/app/report.json"

cat > "$SOLVER" <<'PY'
import json
import sys
from datetime import datetime, timezone

LEVELS = {"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3, "CRITICAL": 4}
PREFIX_TOKENS = 2  # [ts] LEVEL


def parse_line(raw):
    line = raw.rstrip("\n").rstrip("\r")
    tokens = line.split(" ")
    if len(tokens) < 3:
        return None
    ts, level = tokens[0], tokens[1]
    if not (ts.startswith("[") and ts.endswith("Z]") and len(ts) == 22):
        return None
    body = ts[1:-1]
    try:
        datetime.strptime(body, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    if level not in LEVELS:
        return None
    return line, level, " ".join(tokens[2:])


def load_rules(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except Exception:
        return []
    rules = doc.get("rules") if isinstance(doc, dict) else None
    if not isinstance(rules, list):
        return []
    parsed = []
    seen = set()
    for r in rules:
        if not isinstance(r, dict):
            continue
        rid = r.get("id")
        if not isinstance(rid, str) or rid in seen:
            continue
        seen.add(rid)
        keyword = r.get("keyword")
        keyword = keyword if isinstance(keyword, str) else None
        min_level = r.get("min_level")
        min_level = min_level if min_level in LEVELS else "DEBUG"
        threshold = r.get("threshold")
        threshold = threshold if isinstance(threshold, int) and not isinstance(threshold, bool) else 0
        severity = r.get("severity")
        severity = severity if isinstance(severity, str) else "info"
        parsed.append({
            "id": rid, "keyword": keyword, "min_level": min_level,
            "threshold": threshold, "severity": severity,
        })
    return parsed


def clients_of(message):
    out = []
    for tok in message.split():
        if tok.startswith("client=") and len(tok) > len("client="):
            out.append(tok[len("client="):])
    return out


def main():
    rules_path, alert_path, report_path = sys.argv[1], sys.argv[2], sys.argv[3]
    log_paths = sys.argv[4:]
    rules = load_rules(rules_path)

    events = []
    matches = {r["id"]: 0 for r in rules}
    ips = {r["id"]: set() for r in rules}

    for lp in log_paths:
        try:
            with open(lp, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for raw in lines:
            parsed = parse_line(raw)
            if parsed is None:
                continue
            line, level, message = parsed
            for r in rules:
                if r["keyword"] is None:
                    continue
                if r["keyword"] not in line:
                    continue
                if LEVELS[level] < LEVELS[r["min_level"]]:
                    continue
                matches[r["id"]] += 1
                found = clients_of(message)
                ips[r["id"]].update(found)
                events.append({
                    "rule": r["id"],
                    "client": found[0] if found else None,
                    "line": line,
                })

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    alerts = []
    statistics = {}
    for r in rules:
        sorted_ips = sorted(ips[r["id"]])
        if matches[r["id"]] >= r["threshold"]:
            alerts.append({
                "id": r["id"],
                "severity": r["severity"],
                "matches": matches[r["id"]],
                "ips": sorted_ips,
            })
        statistics[r["id"]] = {
            "id": r["id"],
            "keyword": r["keyword"],
            "min_level": r["min_level"],
            "threshold": r["threshold"],
            "severity": r["severity"],
            "matches": matches[r["id"]],
            "unique_ips": len(sorted_ips),
            "ips": sorted_ips,
        }

    with open(alert_path, "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "alerts": alerts}, fh, indent=2)
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump({"timestamp": timestamp, "events": events, "statistics": statistics}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/rules.json "$ALERT" "$REPORT" /app/logs/gateway.log /app/logs/audit.log

echo "solve.sh done -> $SOLVER, $ALERT, $REPORT"
ls -l "$SOLVER" "$ALERT" "$REPORT"
