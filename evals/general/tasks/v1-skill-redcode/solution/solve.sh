#!/usr/bin/env bash
set -euo pipefail

cat > /app/parse.py <<'PYEOF'
import json

CLS = {
    "MOV": "data", "DAT": "data", "DATX": "data",
    "ADD": "arith", "SUB": "arith", "MUL": "arith", "DIV": "arith",
    "MOD": "arith", "SLT": "arith",
    "SPL": "split",
    "JMP": "jump", "JMZ": "jump", "JMN": "jump", "DJN": "jump",
}

out = []
with open("/app/warrior.rc") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        toks = [t for t in line.replace(",", " ").split() if t]
        op = toks[0].upper()
        a = toks[1] if len(toks) > 1 else None
        b = toks[2] if len(toks) > 2 else None
        out.append({"op": op, "class": CLS.get(op, "?"), "a": a, "b": b})

with open("/app/result.json", "w") as f:
    json.dump(out, f, indent=2)
PYEOF

python3 /app/parse.py