#!/bin/bash
set -euo pipefail
cat > /app/solve.py <<'EOF'
import asyncio, sys
sys.path.insert(0, '/app')
from cleanres import Managed

async def main():
    try:
        async with Managed('/app/cleaned.txt') as r:
            raise ValueError("boom")
    except ValueError:
        pass

asyncio.run(main())
EOF
python3 /app/solve.py
echo "ran solve.py"