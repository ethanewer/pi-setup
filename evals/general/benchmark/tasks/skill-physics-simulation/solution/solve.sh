#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
x = 0.0; y = 0.0; vx = 50.0; vy = 60.0
g = 9.81; k = 0.05; dt = 0.1
while True:
    vx = vx + (-k * vx) * dt
    vy = vy + (-g - k * vy) * dt
    x = x + vx * dt
    y = y + vy * dt
    if y < 0.0:
        break
result = round(x, 3)
open('/app/result.txt', 'w').write(f'{result}\n')
print('impact x =', result)
PYEOF