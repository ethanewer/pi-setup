#!/bin/bash
set -euo pipefail
cat > /app/inspect.py <<'PYEOF'
from PIL import Image
img = Image.open('/app/img_info.png')
w, h = img.size
mode = img.mode
r, g, b = img.getpixel((3, 3))
with open('/app/image_info.txt', 'w') as f:
    f.write(f"{w}\n{h}\n{mode}\n{r},{g},{b}\n")
PYEOF
python3 /app/inspect.py