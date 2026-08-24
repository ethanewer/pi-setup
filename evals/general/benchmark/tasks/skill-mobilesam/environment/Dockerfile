FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy

# A tiny MobileSAM-style checkpoint: a promptable segmentation head over a small
# flattened image representation (32x32 grayscale image + a 2-valued point prompt).
# Input vector dim = 32*32 + 2 = 1026; output mask logits dim = 32*32 = 1024.
RUN mkdir -p /app/input /app/model && python3 - <<'PY'
import numpy as np
rng = np.random.default_rng(777)
W_img = rng.normal(0, 0.06, (1026, 32))
b_img = rng.normal(0, 0.03, (32,))
W_mask = rng.normal(0, 0.06, (32, 1024))
b_mask = rng.normal(0, 0.03, (1024,))
np.savez_compressed('/app/model/mobilesam.npz',
                    W_img=W_img, b_img=b_img, W_mask=W_mask, b_mask=b_mask)

img = np.zeros((32, 32), dtype=np.float32)
img[10:16, 12:20] = 1.0
np.save('/app/input/image.npy', img.reshape(1, 1, 32, 32))
with open('/app/input/prompt.txt', 'w') as f:
    f.write("14 15\n")   # a point prompt inside the bright blob
PY