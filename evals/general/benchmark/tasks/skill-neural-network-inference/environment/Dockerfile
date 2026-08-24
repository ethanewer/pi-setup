FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy

# A small 2-layer MLP (6->4->3) and one test feature vector.
RUN mkdir -p /app/data && python3 - <<'PY'
import numpy as np
rng = np.random.default_rng(99)
W1 = rng.normal(0, 0.5, (6, 4))
b1 = rng.normal(0, 0.2, (4,))
W2 = rng.normal(0, 0.5, (4, 3))
b2 = rng.normal(0, 0.2, (3,))
np.savez_compressed('/app/data/net.npz', W1=W1, b1=b1, W2=W2, b2=b2)
x = rng.normal(size=(1, 6)).astype(np.float32)
np.save('/app/data/x.npy', x)
PY