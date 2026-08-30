#!/bin/bash
# Grove bench — oracle: author the six tools, then run them for real.
set -euo pipefail
cd /app

# 1. write the tools (the deliverables an expert agent would produce)
cp /solution/search.py        /app/search.py
cp /solution/expr.py          /app/expr.py
cp /solution/oracle-debug.py  /app/oracle-debug.py
cp /solution/gen-gate.py      /app/gen-gate.py
cp /solution/gen-table.py     /app/gen-table.py
cp /solution/tiny-source.py   /app/tiny-source.py

# 2. run the tile BFS on the shipped puzzle
python3 /app/search.py /app/fixtures/tile_initial.json /app/tile-solution.json

# 3. synthesize the exact expression and materialize it
python3 /app/expr.py /app/fixtures/expr_spec.json > /app/expr.txt

# 4. debug the drift log via the oracle (binary search, both endpoints)
python3 /app/oracle-debug.py /app/fixtures/oracle_ctx.json
# the oracle run materializes both deliverables; fail loudly if missing
[ -s /app/lines.txt ]
[ -s /app/probe-log.json ]

# 5. generate the compact gate netlist (4096-bit XOR tree) under the cap
python3 /app/gen-gate.py 4096 /app/gate.def 32000

# 6. generate the complete substitution table
python3 /app/gen-table.py /app/fixtures/table_spec.json /app/table.csv

# 7. tiny pixel source must run; then report its compressed footprint
python3 /app/tiny-source.py > /dev/null
python3 - <<'PY'
import gzip, json
src = open("/app/tiny-source.py", "rb").read()
json.dump(
    {"source_bytes": len(src), "gzip_bytes": len(gzip.compress(src))},
    open("/app/compressed-sizes.json", "w"),
)
PY

echo "oracle finished"
ls -la /app | grep -E "search|expr|oracle|gen-|gate|table|tiny|tile|lines|probe|compressed"