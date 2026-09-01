import json, random, struct, os

# Deterministic synthetic MNIST-sized model (seeded).
random.seed(1)
H = 32
SCALE = 2 ** -3

w1f = [[random.uniform(-2, 2) for _ in range(H)] for _ in range(784)]
b1f = [random.uniform(-1, 1) for _ in range(H)]
w2f = [[random.uniform(-2, 2) for _ in range(10)] for _ in range(H)]
b2f = [random.uniform(-2, 2) for _ in range(10)]
# Center fc2 columns: no class gets a systematic head start, so predictions
# genuinely depend on the input image.
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


model = {
    "w1": [[real(v) for v in row] for row in w1q],
    "b1": [real(v) for v in b1q],
    "w2": [[real(v) for v in row] for row in w2q],
    "b2": [real(v) for v in b2q],
}
json.dump(model, open("/app/model.json", "w"))

# 60 training-style raw images (784 bytes, 28x28, row-major, values 0-255)
os.makedirs("/app/data", exist_ok=True)


def gen_img(seed):
    random.seed(seed)
    return bytes(random.randint(0, 255) for _ in range(784))


for i in range(60):
    open("/app/data/img_%04d.raw" % i, "wb").write(gen_img(5000 + i))

print("environment ready: model.json, 60 raw images")