#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
from PIL import Image
img = Image.open('/app/photo.png')
width = 160
ratio = img.height / img.width
new_height = round(width * ratio)
resized = img.resize((width, new_height))
resized.save('/app/resized.png')
print('saved /app/resized.png', resized.size)
PYEOF