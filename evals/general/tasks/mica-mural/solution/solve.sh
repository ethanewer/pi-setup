#!/bin/bash
# Oracle for mica-mural: write the parametric renderer (the real work), then
# run it on the shipped spec and report measured sizes. Never reads /tests.
set -eu

cat > /app/mural.py <<'PY'
import gzip
import json
import sys

s = json.load(open(sys.argv[1], encoding="utf-8"))
w, h, p = s["width"], s["height"], s["palette"]
c0, c1, c2, c3, c4, c5 = s["coef"]
m3, m4 = s["mods"]
P = len(p)
rows = []
for y in range(h):
    r = [p[(c0*x + c1*y + c2*x*y + c3*(x*x % m3) + c4*(y*y % m4) + c5) % P]
         for x in range(w)]
    rows.append("".join(r))
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(rows) + "\n")
PY

chmod +x /app/mural.py
python3 /app/mural.py /app/spec.json /app/frame.txt

python3 - <<'PY'
import gzip, json
src = open("/app/mural.py", "rb").read()
rep = {"source_bytes": len(src), "gzip_bytes": len(gzip.compress(src))}
json.dump(rep, open("/app/mural-sizes.json", "w"), indent=2)
print("sizes:", rep)
assert rep["source_bytes"] <= 800 and rep["gzip_bytes"] <= 320, "oracle over cap"
PY

echo "mica-mural oracle done"
