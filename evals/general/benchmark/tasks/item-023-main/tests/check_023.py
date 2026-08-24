# Verifier helper for item-023-main.
# Isolated in tests/ so it is not part of the agent image.
# Derives the ground-truth command order from the video itself via the OCR
# engine, then checks the agent's transcript file.
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, '/app')

CLIP = '/app/clip.mkv'
RESULT = '/app/app/commands.txt'

# 1. Extract frames from the video.
tmp = tempfile.mkdtemp(prefix='vf_')
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', CLIP,
                os.path.join(tmp, 'f_%03d.png')], check=True)
frames = sorted(glob.glob(os.path.join(tmp, 'f_*.png')),
                key=lambda p: int(re.search(r'f_(\d+)\.png', p).group(1)))


def transcribe(path):
    from ocr.ocr import ocr
    return ocr(path).strip()


# 2. Machine transcription of each frame (order), then de-duplicate repeats.
ground = []
for fp in frames:
    t = transcribe(fp)
    if not t:
        continue
    if not ground or ground[-1] != t:
        ground.append(t)


def norm_lines(path):
    out = []
    with open(path) as f:
        for raw in f:
            line = ' '.join(raw.strip().split())
            l = line.lower()
            if l:
                out.append(l)
    return out


got = norm_lines(RESULT)
# The ground truth is lowercase already; normalize lower too.
exp = [g.lower() for g in ground]

assert got == exp
shutil.rmtree(tmp, ignore_errors=True)
print('OK')
sys.exit(0)