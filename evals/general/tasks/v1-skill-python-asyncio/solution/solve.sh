#!/bin/bash
set -euo pipefail

cat > /app/solver.py <<'PYEOF'
import asyncio

async def compute(x):
    await asyncio.sleep(0.5)
    return x * x

async def main():
    results = await asyncio.gather(compute(4), compute(6))
    total = sum(results)
    with open('/app/answer.txt', 'w') as f:
        f.write(f'total squares = {total}\n')

if __name__ == '__main__':
    asyncio.run(main())
PYEOF

python3 /app/solver.py
echo "wrote /app/answer.txt"