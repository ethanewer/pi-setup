#!/bin/bash
# Oracle solution for item-032-main: write a PTY driver, run it, confirm token.
set -euo pipefail

cat > /app/driver.py <<'PYEOF'
#!/usr/bin/env python3
"""Drive /app/vault.sh through a PTY: answer the three gates, grab the token."""
import os, pty, re, select, time, sys

ANSI = re.compile(rb'\x1b\[[0-9;?]*[A-Za-z]')
PROMPT = re.compile(rb'(-?\d+)\s*([-+*/])\s*(-?\d+)\s*=\s*\?')

def main():
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", "/app/vault.sh"])
    buf = b""

    def drain(timeout):
        nonlocal buf
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if not r:
                return
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                return
            if not chunk:
                return
            buf += chunk

    def wait(pred, timeout=25):
        end = time.time() + timeout
        while not pred(buf):
            if time.time() > end:
                return False
            drain(0.5)
        return True

    for gate in range(3):
        if not wait(lambda b: len(PROMPT.findall(b)) >= gate + 1):
            print("prompt timeout", file=sys.stderr)
            return 1
        a, op, bval = PROMPT.findall(buf)[gate]
        if op == b'+':
            ans = int(a) + int(bval)
        elif op == b'*':
            ans = int(a) * int(bval)
        elif op == b'/':
            ans = int(a) // int(bval)
        else:
            ans = int(a) - int(bval)
        os.write(fd, ("%d" % ans).encode() + b"\r")
        time.sleep(0.2)

    if not wait(lambda b: re.search(rb'GOLDEN-\d+', ANSI.sub(b'', b)) is not None, 25):
        print("token timeout", file=sys.stderr)
        return 1
    clean = ANSI.sub(b'', buf)
    tok = re.search(rb'GOLDEN-\d+', clean).group()
    with open("/app/result.txt", "wb") as f:
        f.write(tok + b"\n")
    try:
        os.close(fd)
    except OSError:
        pass
    return 0

sys.exit(main())
PYEOF

# Run it and self-check
python3 /app/driver.py || { echo "driver failed"; exit 1; }
if [ "$(tr -d '\r\n' < /app/result.txt)" = "GOLDEN-2112" ]; then
  echo "OK: $(cat /app/result.txt)"
else
  echo "result mismatch: [$(cat /app/result.txt)]"
  exit 1
fi
echo DONE