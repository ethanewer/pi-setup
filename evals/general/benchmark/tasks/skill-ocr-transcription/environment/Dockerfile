FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr fonts-dejavu-core python3-pip && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages --disable-pip-version-check pillow

# Generate the quote image deterministically with PIL.
RUN python3 - <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (640, 240), 'white')
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 42)

d.text((40, 30), 'ALL WORK AND NO PLAY', font=font, fill='black')
d.text((40, 110), 'MAKES JACK A DULL BOY', font=font, fill='black')

img.save('/app/quote.png', 'PNG')
PYEOF