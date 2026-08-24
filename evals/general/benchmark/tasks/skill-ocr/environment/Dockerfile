FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr fonts-dejavu-core python3-pip && rm -rf /var/lib/apt/lists/*

RUN pip install --disable-pip-version-check --break-system-packages pillow

# Generate the OCR test image deterministically with PIL (DejaVu Sans Bold, 64px).
RUN python3 - <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (640, 120), 'white')
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 64)
d.text((20, 22), 'HARBOR42', font=font, fill='black')
img.save('/app/ocr.png', 'PNG')
PYEOF