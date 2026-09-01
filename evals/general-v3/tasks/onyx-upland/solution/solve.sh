#!/usr/bin/env bash
# Oracle for onyx-upland: writes the five reporting programs and runs them on
# the shipped /app fixtures to produce the five derived artifacts.
set -euo pipefail

cd /app

cat > /app/aggregate.py <<'PY'
import sys, csv

def main():
    inp, out = sys.argv[1], sys.argv[2]
    header = None
    data = []
    with open(inp, newline='') as f:
        for row in csv.reader(f):
            if not row or all(c.strip() == '' for c in row):
                continue
            if header is None:
                header = row
                continue
            data.append(row)
    cats = {}
    for r in data:
        if len(r) < 3:
            continue
        cat = r[0].strip()
        amt = int(r[1])
        qty = int(r[2])
        if cat not in cats:
            cats[cat] = [0, 0]
        cats[cat][0] += amt
        cats[cat][1] += qty
    with open(out, 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['category', 'total_amount', 'total_qty'])
        for cat in sorted(cats):
            w.writerow([cat, cats[cat][0], cats[cat][1]])
        ta = sum(cats[c][0] for c in cats)
        tq = sum(cats[c][1] for c in cats)
        w.writerow(['TOTAL', ta, tq])

if __name__ == '__main__':
    main()
PY

cat > /app/ordered.py <<'PY'
import sys, csv

def main():
    inp, out = sys.argv[1], sys.argv[2]
    header = None
    rows = []
    with open(inp, newline='') as f:
        for row in csv.reader(f):
            if not row or all(c.strip() == '' for c in row):
                continue
            if header is None:
                header = row
                continue
            if len(row) < 4:
                continue
            pid = row[0].strip()
            status = row[1].strip()
            rev = int(row[2])
            prio = int(row[3])
            if status == 'accepted':
                rows.append((pid, rev, prio))
    rows.sort(key=lambda x: (-x[1], x[2], x[0]))
    with open(out, 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['product_id', 'revenue', 'priority'])
        for pid, rev, prio in rows:
            w.writerow([pid, rev, prio])

if __name__ == '__main__':
    main()
PY

cat > /app/tally.py <<'PY'
import sys, csv

def main():
    inp, out = sys.argv[1], sys.argv[2]
    header = None
    total = 0
    nf = 0
    ids = []
    with open(inp, newline='') as f:
        for row in csv.reader(f):
            if not row or all(c.strip() == '' for c in row):
                continue
            if header is None:
                header = row
                continue
            if len(row) < 3:
                continue
            total += 1
            rid = row[0].strip()
            status = row[2].strip()
            if status == 'not_found':
                nf += 1
                ids.append(rid)
    with open(out, 'w') as f:
        f.write('=== SCAN TALLY ===\n')
        f.write('total=%d\n' % total)
        f.write('resolved=%d\n' % (total - nf))
        f.write('not_found=%d\n' % nf)
        f.write('=== NOT-FOUND ENTRIES ===\n')
        for i in ids:
            f.write('%s\n' % i)

if __name__ == '__main__':
    main()
PY

cat > /app/frames.py <<'PY'
import sys

def main():
    inp, out = sys.argv[1], sys.argv[2]
    start = None
    stop = None
    with open(inp) as f:
        for line in f:
            line = line.rstrip('\n').rstrip('\r')
            if not line.strip() or line.strip().startswith('#'):
                continue
            if '=' in line:
                k, v = line.split('=', 1)
                k = k.strip()
                v = v.strip()
                if k == 'start':
                    start = int(v)
                elif k == 'stop':
                    stop = int(v)
    low = min(start, stop)
    high = max(start, stop)
    with open(out, 'w') as f:
        f.write('low = %d\n' % low)
        f.write('high = %d\n' % high)

if __name__ == '__main__':
    main()
PY

cat > /app/fixed_width.py <<'PY'
import sys, csv

W = dict(seq=4, name=8, code=5, value=8)

def main():
    inp, out = sys.argv[1], sys.argv[2]
    header = None
    recs = []
    with open(inp, newline='') as f:
        for row in csv.reader(f):
            if not row or all(c.strip() == '' for c in row):
                continue
            if header is None:
                header = row
                continue
            recs.append(row)
    buf = []
    for r in recs:
        if len(r) < 4:
            continue
        seq = int(r[0].strip())
        name = r[1].strip()
        code = r[2].strip()
        value = int(r[3].strip())
        line = '%4d%-8s%-5s%8d' % (seq, name[:8], code[:5], value)
        buf.append(line.encode('ascii') + b'\n')
    with open(out, 'wb') as f:
        f.write(b''.join(buf))

if __name__ == '__main__':
    main()
PY

chmod +x /app/aggregate.py /app/ordered.py /app/tally.py /app/frames.py /app/fixed_width.py

python3 /app/aggregate.py /app/sales.csv /app/summary.csv
python3 /app/ordered.py /app/orders.csv /app/results.csv
python3 /app/tally.py /app/statuses.csv /app/report.txt
python3 /app/frames.py /app/frames.conf /app/frames.toml
python3 /app/fixed_width.py /app/inventory.csv /app/records.bin

echo "oracle done"