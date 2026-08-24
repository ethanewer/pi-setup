FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr fonts-dejavu-core python3-pil && rm -rf /var/lib/apt/lists/*

# Generate the badge image deterministically with PIL.
RUN python3 - <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (640, 240), (255, 250, 230))
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 56)

d.text((40, 20), 'ZONE B7', font=font, fill='black')
d.text((40, 90), 'ID 0183', font=font, fill='black')
d.text((40, 160), 'NAME ALICE', font=font, fill='black')

img.save('/app/badge.png', 'PNG')
PYEOF