#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
agg = {}
with open('/app/data/measurements.txt') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        st, temp = line.split(';')
        t = float(temp)
        if st not in agg:
            agg[st] = [t, t, t, 1]   # min, max, sum, count
        else:
            a = agg[st]
            if t < a[0]: a[0] = t
            if t > a[1]: a[1] = t
            a[2] += t
            a[3] += 1
with open('/app/results.txt', 'w') as out:
    for st in sorted(agg):
        mn, mx, s, c = agg[st]
        mean = round(s / c, 1)
        out.write(f"{st};{mn:.1f};{mx:.1f};{mean:.1f}\n")
print("wrote results")
EOF