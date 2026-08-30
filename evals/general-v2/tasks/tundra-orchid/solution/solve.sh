#!/usr/bin/env bash
set -euo pipefail

cat > /app/analyze_logs.py <<'PY'
import re, sys

PAT = re.compile(
    r'^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\]'
    r'\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d{3})\s+(\d+)$'
)

def requests(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = PAT.match(line.strip())
            if m:
                ts, ip, method, path_tok, status, size = m.groups()
                out.append((ts, ip, method, path_tok, int(status), int(size)))
    return out

if __name__ == "__main__":
    import sys
    reqs = requests(sys.argv[1])
    ip = set(r[1] for r in reqs)
    sys.stdout.write(f"total_requests={len(reqs)}\n")
    sys.stdout.write(f"unique_clients={len(ip)}\n")
PY
chmod +x /app/analyze_logs.py

cat > /app/answer.py <<'PY'
import re, sys

PAT = re.compile(
    r'^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\]'
    r'\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d{3})\s+(\d+)$'
)

def requests(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = PAT.match(line.strip())
            if m:
                ts, ip, method, path_tok, status, size = m.groups()
                out.append((ts, ip, method, path_tok, int(status), int(size)))
    return out

def main(argv):
    ts500 = [r[0] for r in requests(argv[1]) if r[4] == 500]
    print(min(ts500) if ts500 else "NONE")

main(sys.argv)
PY
chmod +x /app/answer.py

cat > /app/metric.py <<'PY'
import json, re, sys

PAT = re.compile(
    r'^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\]'
    r'\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d{3})\s+(\d+)$'
)

def main(argv):
    total = 0
    accepted = 0
    with open(argv[1], encoding="utf-8") as fh:
        for line in fh:
            m = PAT.match(line.strip())
            if m:
                ts, ip, method, path_tok, status, size = m.groups()
                st = int(status)
                total += 1
                if 200 <= st <= 299:
                    accepted += 1
    rate = f"{accepted/total:.3f}" if total else "0.000"
    print(json.dumps({"accepted": accepted, "total": total, "acceptance_rate": rate}))

main(sys.argv)
PY
chmod +x /app/metric.py

cat > /app/fixed_script.py <<'PY'
import sys

def main(argv):
    infile, outfile = argv[1], argv[2]
    records = []
    with open(infile, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip("\n").strip("\r")
            if line.strip() == "":
                continue
            cols = line.split(",")
            if len(cols) != 2:
                continue
            name = cols[0].strip().lower()
            qty = cols[1].strip()
            if name == "" or qty == "":
                continue
            records.append((name, qty))
    with open(outfile, "w", encoding="utf-8") as fh:
        for name, qty in records:
            fh.write(name + "," + qty + "\n")

main(sys.argv)
PY
chmod +x /app/fixed_script.py

cat > /app/merge_records.py <<'PY'
import json, sys

def main():
    rows = []
    with open(sys.argv[1], encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    for idx, line in enumerate(lines):
        if idx == 0:
            continue  # header
        line = line.strip()
        if line == "":
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 4:
            continue
        user, field, source, value = parts
        rows.append((user, field, source, value))

    seen = {}
    order = []
    for i, (user, field, source, value) in enumerate(rows):
        key = (user, field)
        if key not in seen:
            seen[key] = i
            order.append(key)

    bypair = {}
    for user, field, source, value in rows:
        bypair.setdefault((user, field), {})[source] = value

    conflicts = []
    for user, field in order:
        d = bypair[(user, field)]
        if "primary" in d and "backup" in d and d["primary"] != d["backup"]:
            conflicts.append({
                "user": user,
                "field": field,
                "sources": [
                    {"source": "primary", "value": d["primary"]},
                    {"source": "backup", "value": d["backup"]},
                ],
                "winner": d["primary"],
            })
    print(json.dumps({"total_conflicts": len(conflicts), "conflicts": conflicts}))

main()
PY
chmod +x /app/merge_records.py

# Produce the report artifacts by actually running the work.
python3 /app/analyze_logs.py /app/sample_access.log > /app/log_report.txt
python3 /app/answer.py /app/sample_access.log > /app/answer.txt
python3 /app/metric.py /app/sample_access.log > /app/metric.json
python3 /app/fixed_script.py /app/sample_records.csv /app/fixed_output.csv
python3 /app/merge_records.py /app/people_records.csv > /app/conflict_report.json

echo "solve.sh complete"
ls -1 /app/analyze_logs.py /app/log_report.txt /app/answer.py /app/answer.txt \
   /app/metric.py /app/metric.json /app/fixed_script.py /app/fixed_output.csv \
   /app/merge_records.py /app/conflict_report.json