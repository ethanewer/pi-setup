#!/bin/bash
# flint-orchid oracle: author the reusable tools, then run them over the
# baked visible fixtures to produce every deliverable. Never reads /tests.
set -euo pipefail

install -m 0644 /solution/parse_form.py     /app/parse_form.py
install -m 0644 /solution/parse_financials.py /app/parse_financials.py
install -m 0644 /solution/decode_mesh.py    /app/decode_mesh.py
install -m 0644 /solution/query.rq          /app/query.rq
chmod +x /app/parse_form.py /app/parse_financials.py /app/decode_mesh.py

# 1) PDF form fields
python3 /app/parse_form.py /app/data/registration_form.pdf /app/form_fields.json

# 2) financial metrics + rows
python3 /app/parse_financials.py /app/data/financials.html /app/financials.json

# 3) SPARQL relationship query -> results.csv (header person,org)
python3 - <<'PY'
from rdflib import Graph
import csv
g = Graph()
g.parse('/app/data/relations.ttl', format='turtle')
q = open('/app/query.rq').read()
rows = sorted({(str(r[0]), str(r[1])) for r in g.query(q)})
with open('/app/results.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['person', 'org'])
    w.writerows(rows)
print('wrote %d result rows' % len(rows))
PY

# 4) skinned-mesh decode -> npz
python3 /app/decode_mesh.py /app/data/rigged_pump.bin /app/mesh_arrays.npz

# sanity: every deliverable exists
for f in /app/form_fields.json /app/financials.json /app/query.rq /app/results.csv \
         /app/decode_mesh.py /app/mesh_arrays.npz \
         /app/parse_form.py /app/parse_financials.py; do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done
echo "flint-orchid oracle complete"
