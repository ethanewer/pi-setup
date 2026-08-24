FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
import csv
rows = [
    ['item', 'amount'],
    ['widget', '10'],
    ['gadget', '25'],
    ['doohickey', '5'],
    ['thing', '40'],
]
with open('/app/sales.csv', 'w', newline='') as f:
    csv.writer(f).writerows(rows)
PYEOF