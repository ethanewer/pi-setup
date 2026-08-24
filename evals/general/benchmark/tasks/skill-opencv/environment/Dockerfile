FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy opencv-python-headless

# Generate the test image with OpenCV at build time (deterministic):
# 200x200 white, one 60x60 solid red rectangle.
RUN python3 - <<'PYEOF'
import numpy as np
import cv2

img = np.full((200, 200, 3), 255, dtype=np.uint8)
cv2.rectangle(img, (40, 50), (99, 109), (0, 0, 255), thickness=-1)  # BGR red
cv2.imwrite('/app/shapes.png', img)
PYEOF