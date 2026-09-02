#!/bin/bash
set -euo pipefail
cat > /app/solve.py <<'EOF'
import asyncio, json, sys
sys.path.insert(0, '/app')
from tasklib import long_task

async def main():
    markers = {}
    tasks = [asyncio.create_task(long_task('t1', markers)),
             asyncio.create_task(long_task('t2', markers))]
    await asyncio.sleep(0.2)
    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    return markers

markers = asyncio.run(main())
with open('/app/cancellation.json', 'w') as f:
    json.dump({'t1_cancelled': bool(markers.get('t1', False)),
               't2_cancelled': bool(markers.get('t2', False))}, f)
EOF
python3 /app/solve.py
echo "ran solve.py"