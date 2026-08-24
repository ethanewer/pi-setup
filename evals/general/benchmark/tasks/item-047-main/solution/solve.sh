#!/bin/bash
set -euo pipefail

mkdir -p /app/evidence /app/report

RAW="https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md"
curl -fsSL "$RAW" -o /app/evidence/README.md

python3 - <<'PY'
import datetime, json, re

md = open("/app/evidence/README.md", encoding="utf-8", errors="replace").read()
lines = md.splitlines()

# locate the C-MTEB header row: contains 'Embedding dimension' and 'Avg' and 'STS'
cmt_idx = None
for i, ln in enumerate(lines):
    if ln.startswith("|") and "Embedding dimension" in ln and "Avg" in ln and "STS" in ln:
        cmt_idx = i
        break
assert cmt_idx is not None, "C-MTEB table header not found"

def cells(line):
    parts = line.strip().strip("|").split("|")
    return [p.strip() for p in parts]

rows = []
for ln in lines[cmt_idx + 1:]:
    if not ln.startswith("|"):
        break
    c = cells(ln)
    if len(c) < 8 or not c[0]:
        continue
    try:
        avg = float(c[2])
    except ValueError:
        continue
    rows.append((c[0], avg, c))

# find target model row
target = None
for name, avg, c in rows:
    if "bge-small-zh-v1.5" in name:
        target = (name, avg, c)
        break
assert target is not None, "model row not found"
name, avg, c = target

avg_cell = float(c[2])
sts_cell = float(c[4])
total = len(rows)
rank = 1 + sum(1 for _, a, _ in rows if a > avg_cell)

report = {
    "model_id": "BAAI/bge-small-zh-v1.5",
    "benchmark": "C-MTEB",
    "column_input": "Avg",
    "value_avg": avg_cell,
    "value_sts": sts_cell,
    "rank": rank,
    "total": total,
    "evidence_date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "source_url": "https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md",
}
with open("/app/report/report.json", "w") as f:
    json.dump(report, f, indent=2)
print(json.dumps(report))
PY