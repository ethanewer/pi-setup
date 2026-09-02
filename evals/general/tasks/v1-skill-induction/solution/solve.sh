#!/bin/bash
set -euo pipefail
cat > /app/induced.py <<'PYEOF'
total = 0
for k in range(1, 101):
    total += 2 * k - 1
    assert total == k * k, (k, total)
open('/app/answer.txt', 'w').write(str(total))
PYEOF
python3 /app/induced.py