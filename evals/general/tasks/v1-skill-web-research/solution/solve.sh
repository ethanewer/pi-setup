#!/bin/bash
set -euo pipefail

cat > /app/research.py <<'EOF'
import json
import re

with open("/app/report.html", encoding="utf-8") as f:
    html = f.read()

title = re.search(r"<title>(.*?)</title>", html, re.S).group(1).strip()

# extract table rows: <td>label</td><td>value</td>
rows = re.findall(r"<td>(.*?)</td>\s*<td>(.*?)</td>", html, re.S)
data = {k.strip().lower(): v.strip() for k, v in rows}

out = {
    "title": title,
    "revenue": data.get("revenue", ""),
    "founded": data.get("founded", ""),
    "headquarters": data.get("headquarters", ""),
}

with open("/app/research.json", "w") as f:
    json.dump(out, f)
EOF

python3 /app/research.py