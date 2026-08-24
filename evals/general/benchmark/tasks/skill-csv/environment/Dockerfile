FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
import csv
rows = [
    ['id', 'name', 'dept'],
    ['1', 'Smith, Jane', 'sales'],
    ['2', 'Brown, Alice', 'engineering'],
    ['3', 'Miller, Paul', 'support'],
    ['4', 'Davis, Emma', 'research'],
]
with open('/app/people.csv', 'w', newline='') as f:
    csv.writer(f).writerows(rows)
PYEOF