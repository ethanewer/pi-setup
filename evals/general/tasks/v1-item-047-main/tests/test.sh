#!/bin/bash
mkdir -p /logs/verifier

if [ ! -f /app/report/report.json ]; then
  echo "0.0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json, os, re, sys, datetime, subprocess

try:
    report = json.load(open("/app/report/report.json"))
    md = ""
    if os.path.exists("/app/evidence/README.md"):
        md = open("/app/evidence/README.md", encoding="utf-8", errors="replace").read()
except Exception:
    open("/logs/verifier/reward.txt", "w").write("0.0")
    sys.exit(0)

def normalize(url):
    url = url.strip()
    if re.search(r"huggingface\.co/BAAI/bge-small-zh-v1\.5(/blob/main/README\.md)?/?$", url):
        return "https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md"
    if re.search(r"huggingface\.co/BAAI/bge-small-zh-v1\.5/raw/main/README\.md", url):
        return "https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md"
    return None

src_norm = normalize(report.get("source_url", ""))

# parse the C-MTEB table from the evidence snapshot (network fallback not needed:
# the snapshot is the agent's own captured evidence and is authoritative for grading)
lines = md.splitlines()
hdr_i = None
for i, ln in enumerate(lines):
    if ln.startswith("|") and "Embedding dimension" in ln and "Avg" in ln and "STS" in ln:
        hdr_i = i
        break

def cells(ln):
    return [c.strip() for c in ln.strip().strip("|").split("|")]

def parse_rows():
    rows = []
    if hdr_i is None:
        return rows
    for ln in lines[hdr_i + 1:]:
        if not ln.startswith("|"):
            break
        c = cells(ln)
        if len(c) < 8:
            continue
        try:
            avg = float(c[2])
        except ValueError:
            continue
        rows.append((c, avg))
    return rows

def do_checks():
    checks = {}
    checks["keys"] = all(k in report for k in
        ["model_id", "benchmark", "column_input", "value_avg", "value_sts",
         "rank", "total", "evidence_date", "source_url"])
    checks["model"] = report.get("model_id") == "BAAI/bge-small-zh-v1.5"
    checks["benchmark"] = report.get("benchmark") == "C-MTEB"
    checks["column_input"] = report.get("column_input") == "Avg"
    rows = parse_rows()
    target = None
    for c, avg in rows:
        if any("bge-small-zh-v1.5" in x.lower() for x in c):
            target = (c, avg)
            break
    checks["table_found"] = target is not None
    if target is None:
        return checks
    tc, tavg = target
    tsts = float(tc[4])
    total = len(rows)
    rank = 1 + sum(1 for _, a in rows if a > tavg)
    checks["value_avg"] = (isinstance(report.get("value_avg"), (int, float))
                           and abs(float(report["value_avg"]) - tavg) <= 0.01)
    checks["value_sts"] = (isinstance(report.get("value_sts"), (int, float))
                           and abs(float(report["value_sts"]) - tsts) <= 0.01)
    checks["rank"] = report.get("rank") == rank and isinstance(report.get("rank"), int)
    checks["total"] = report.get("total") == total and isinstance(report.get("total"), int)
    checks["source_ok"] = src_norm is not None
    try:
        ed = datetime.datetime.strptime(report["evidence_date"], "%Y-%m-%d")
        days = abs((ed - datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)).days)
        checks["evidence_date"] = days <= 3
    except Exception:
        checks["evidence_date"] = False
    checks["evidence_has_row"] = ("bge-small-zh-v1.5" in md and "C-MTEB" in md
                                  and f"{tsts:.2f}" in md)
    return checks

checks = do_checks()
tot = sum(1 for v in checks.values() if v)
if tot == len(checks):
    reward = 1.0
elif tot >= len(checks) - 2:
    reward = 0.5
else:
    reward = 0.0
open("/logs/verifier/reward.txt", "w").write(repr(reward))
print(checks, file=sys.stderr)
PY