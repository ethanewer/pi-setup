#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/report.txt ]; then
  if python3 - <<'PYEOF'
import subprocess, os
subprocess.run('ffmpeg -y -i /app/video.mp4 -ss 2.5 -frames:v 1 -f rawvideo -pix_fmt rgb24 -s 16x16 /tmp/frame.rgb'.split(), check=True)
with open('/tmp/frame.rgb','rb') as f:
    raw = f.read()
n = 16*16
r = sum(raw[i*3+0] for i in range(n))/n
g = sum(raw[i*3+1] for i in range(n))/n
b = sum(raw[i*3+2] for i in range(n))/n
exp = f"{round(r)} {round(g)} {round(b)}"
with open('/app/report.txt') as f:
    got = f.read().strip()
assert got == exp
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt