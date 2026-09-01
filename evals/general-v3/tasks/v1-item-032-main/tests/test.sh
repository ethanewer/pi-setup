#!/bin/bash
# Verifier for item-032-main.
# 1) drive vault.sh independently through a PTY: it must open and print the token
# 2) (re)run the agent's driver and check /app/result.txt carries the token
mkdir -p /logs/verifier
reward=0

replay_ok=$(python3 - <<'EOF'
import os, pty, re, select, time, sys
ret = 0
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "/app/vault.sh"])
buf = b""
def drain(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            continue
        try:
            c = os.read(fd, 4096)
        except OSError:
            return
        if not c:
            return
        buf += c
for ans in ("36", "126", "27"):
    drain(0.4)
    os.write(fd, ans.encode() + b"\r")
    drain(1.0)
time.sleep(4)
drain(3.0)
clean = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', buf)
print(1 if b"GOLDEN-2112" in clean else 0)
try:
    os.close(fd)
except OSError:
    pass
EOF
)

driver_ok=0
if [ -f /app/driver.py ]; then
  rm -f /app/result.txt
  if timeout 90 python3 /app/driver.py >/dev/null 2>&1; then
    if [ -f /app/result.txt ]; then
      got=$(tr -d '\r\n' < /app/result.txt)
      [ "$got" = "GOLDEN-2112" ] && driver_ok=1
    fi
  fi
fi

if [ "$replay_ok" = "1" ] && [ "$driver_ok" = "1" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt