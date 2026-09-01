import json, random, struct, os

# Deterministic synthetic MNIST-sized model (seeded) - SAME weights as the
# "main" variant so the ground truth is easily cross-checkable.
random.seed(1)
H = 32
SCALE = 2 ** -3

w1f = [[random.uniform(-2, 2) for _ in range(H)] for _ in range(784)]
b1f = [random.uniform(-1, 1) for _ in range(H)]
w2f = [[random.uniform(-2, 2) for _ in range(10)] for _ in range(H)]
b2f = [random.uniform(-2, 2) for _ in range(10)]
for j in range(10):
    m = sum(w2f[i][j] for i in range(H)) / H
    for i in range(H):
        w2f[i][j] -= m


def q(x):
    v = int(round(x / SCALE))
    return max(-127, min(127, v))


w1q = [[q(v) for v in row] for row in w1f]   # 784 x 32
b1q = [q(v) for v in b1f]
w2q = [[q(v) for v in row] for row in w2f]   # 32 x 10
b2q = [q(v) for v in b2f]


def real(v):
    return v * SCALE


# ---- ground truth: PyTorch-style state dict (out, in) layout ----
state = {
    "fc1.weight": [[real(w1q[k][i]) for k in range(784)] for i in range(H)],  # [32][784]
    "fc1.bias": [real(v) for v in b1q],
    "fc2.weight": [[real(w2q[i][j]) for i in range(H)] for j in range(10)],  # [10][32]
    "fc2.bias": [real(v) for v in b2q],
    "scale": SCALE,
}
json.dump(state, open("/app/model_pytorch.json", "w"))

# ---- undocumented compact binary: header + int8 payload ----
# header: 4-byte magic "Q8V1" | float32 scale | 4 x uint32 lengths
# payload (int8, row-major, PyTorch layout):
#   fc1.weight [32][784] (25088) | fc1.bias (32) | fc2.weight [10][32] (320) | fc2.bias (10)
with open("/app/weights_q8.bin", "wb") as f:
    f.write(b"Q8V1")
    f.write(struct.pack("<f", SCALE))
    for n in (784 * H, H, 10 * H, 10):
        f.write(struct.pack("<I", n))
    for i in range(H):
        for k in range(784):
            f.write(struct.pack("<b", w1q[k][i]))
    for v in b1q:
        f.write(struct.pack("<b", v))
    for j in range(10):
        for i in range(H):
            f.write(struct.pack("<b", w2q[i][j]))
    for v in b2q:
        f.write(struct.pack("<b", v))

# ---- 60 raw images (same as main) ----
os.makedirs("/app/data", exist_ok=True)


def gen_img(seed):
    random.seed(seed)
    return bytes(random.randint(0, 255) for _ in range(784))


for i in range(60):
    open("/app/data/img_%04d.raw" % i, "wb").write(gen_img(5000 + i))

print("environment ready: model_pytorch.json, weights_q8.bin, notes.txt, 60 images")