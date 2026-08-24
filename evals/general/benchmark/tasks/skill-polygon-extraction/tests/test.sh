#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/shape.svg" ] && [ -f "$APP/polygon.txt" ] && [ -f "$APP/area.txt" ] && [ -f "$APP/perimeter.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import re, math, sys
base = sys.argv[1]
svg = open(base + '/shape.svg').read()
m = re.search(r'points="([^"]+)"', svg)
if m is None:
    sys.exit(1)
pts = [tuple(map(int, p.split(','))) for p in m.group(1).split()]
n = len(pts)
if n < 3:
    sys.exit(1)
area = 0.5 * abs(sum(pts[i][0]*pts[(i+1) % n][1] - pts[(i+1) % n][0]*pts[i][1] for i in range(n)))
per = sum(math.hypot(pts[(i+1) % n][0]-pts[i][0], pts[(i+1) % n][1]-pts[i][1]) for i in range(n))
exp_poly = sorted(pts)
got_lines = [l.strip() for l in open(base + '/polygon.txt') if l.strip()]
try:
    got_poly = sorted(tuple(map(int, p.split(','))) for p in got_lines if p)
except Exception:
    sys.exit(1)
try:
    got_area = float(open(base + '/area.txt').read().strip())
    got_per = float(open(base + '/perimeter.txt').read().strip())
except Exception:
    sys.exit(1)
ok = (got_poly == exp_poly) and abs(got_area - area) < 1e-3 and abs(got_per - per) < 1e-3
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt