#!/bin/bash
set -euo pipefail
cat > /app/solver.py <<'EOF'
import asyncio, sys
sys.path.insert(0, '/app')

async def run_tag(tag):
    proc = await asyncio.create_subprocess_exec(
        sys.executable, '/app/talker.py', tag,
        stdout=asyncio.subprocess.PIPE)
    data = await proc.stdout.read()
    await proc.wait()
    return data.decode().strip()

async def main():
    a = asyncio.create_task(run_tag('alpha'))
    b = asyncio.create_task(run_tag('beta'))
    outs = await asyncio.gather(a, b)
    print("\n".join(outs))

if __name__ == '__main__':
    asyncio.run(main())
EOF
echo "wrote solver.py"