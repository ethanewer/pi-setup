#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/frames.json ]; then
  if python3 - <<'PYEOF'
import json, glob, subprocess, struct
pngs = sorted(glob.glob('/app/frames/frame_*.png'))
assert pngs, 'no frames extracted'
# verify PNG dimensions consistent with 160x120
def dims(p):
    with open(p,'rb') as f:
        head = f.read(24)
    assert head[:8] == b'\x89PNG\r\n\x1a\n'
    w, h = struct.unpack('>II', head[16:24])
    return w, h
wh = set(dims(p) for p in pngs)
assert wh == {(160, 120)}, wh
nb = int(subprocess.run(['ffprobe','-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=nb_read_frames','-of','csv=p=0','/app/sample.mp4'], capture_output=True, text=True).stdout.strip() or 0)
got = json.load(open('/app/frames.json'))
exp = {'frames': len(pngs), 'width': 160, 'height': 120}
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt