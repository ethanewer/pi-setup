#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/image_info.txt ]; then
  if python3 - <<'PYEOF'
from PIL import Image
img = Image.open('/app/img_info.png')
w, h = img.size
r, g, b = img.getpixel((3, 3))
exp = f"{w}\n{h}\n{img.mode}\n{r},{g},{b}\n"
got = open('/app/image_info.txt').read()
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt