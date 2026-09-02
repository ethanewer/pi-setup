FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy

# Create a small MNIST-style trained network snapshot and a single test image.
# The image is a 28x28 flattened grayscale digit (1,784) and the model is a 2-layer MLP.
RUN mkdir -p /app/data && python3 - <<'PY'
import numpy as np
rng = np.random.default_rng(202407)
W1 = rng.normal(0, 0.08, (784, 64))
b1 = rng.normal(0, 0.05, (64,))
W2 = rng.normal(0, 0.08, (64, 10))
b2 = rng.normal(0, 0.05, (10,))
np.savez_compressed('/app/data/model.npz', W1=W1, b1=b1, W2=W2, b2=b2)
# A test image that looks digit-like: a small blob in the upper left.
x = np.zeros(784, dtype=np.float32)
x[6*28+8:6*28+12] = 0.8
x[7*28+8:7*28+12] = 0.8
x[11*28+4:11*28+10] = 0.15
np.save('/app/data/x.npy', x.reshape(1, 784).astype(np.float32))
PY