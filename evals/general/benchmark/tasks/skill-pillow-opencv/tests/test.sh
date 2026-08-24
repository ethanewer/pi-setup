#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/resized.png ] && [ -f /app/photo.png ]; then
python3 - <<'PYEOF'
import sys
try:
    from PIL import Image
    src = Image.open('/app/photo.png')
    target_w = 160
    ratio = src.height / src.width
    exp_h = round(target_w * ratio)
    img = Image.open('/app/resized.png')
    fmt = (img.format or '').upper()
    ok = (img.size == (target_w, exp_h)) and ('PNG' in fmt)
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt