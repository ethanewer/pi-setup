FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy pillow opencv-python-headless

# Generate the test image with Pillow (deterministic): 200x200 white, one solid
# green filled circle, bounding box (60,60)-(140,140).
RUN python3 - <<'PYEOF'
from PIL import Image, ImageDraw

img = Image.new('RGB', (200, 200), 'white')
d = ImageDraw.Draw(img)
d.ellipse((60, 60, 140, 140), fill=(0, 255, 0))
img.save('/app/circle.png', 'PNG')
PYEOF