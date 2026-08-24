#!/bin/bash
set -euo pipefail

cat > /app/pty_runner.py <<'PYEOF'
import os
import pty
import subprocess
import select

master, slave = pty.openpty()
p = subprocess.Popen(
    ['python3', '/app/printer.py'],
    stdin=subprocess.PIPE,
    stdout=slave,
    stderr=slave,
    close_fds=True,
)
os.close(slave)

data = b''
while True:
    r, _, _ = select.select([master], [], [], 1.0)
    if not r:
        if p.poll() is not None:
            break
        continue
    try:
        chunk = os.read(master, 1024)
    except OSError:
        # pty master raises EIO when the child closes its side
        break
    if not chunk:
        break
    data += chunk

os.close(master)
p.wait()

with open('/app/pty_out.txt', 'wb') as f:
    f.write(data)
PYEOF

python3 /app/pty_runner.py
echo "wrote /app/pty_out.txt"