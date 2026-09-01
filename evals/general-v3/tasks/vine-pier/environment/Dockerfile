FROM bench-base:python-3.12

# vine-pier: a small-model lab.  The "Vertex" lab ships a transformer check-
# point in a bespoke binary format plus a byte-pair vocabulary, all local, no
# network.  The agent must author a dependency-free C reader for the checkpoint
# and vocabulary plus three model-computation programs, then persist the fitted
# model and a structured parameters report.  Only C toolchain + numpy needed.
RUN apt-get update -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m pip install --quiet numpy tomli

WORKDIR /app

# Create the shipped local fixtures: a small "Vertex" checkpoint in the custom
# VINER1 format and its byte-pair vocabulary (deterministic, seeded).  The
# loader/arithmetic is *not* shipped to /app -- it is the agent's job to build
# every parser and model program from scratch per instruction.md.
RUN mkdir -p /app/data && python3 - <<'PY'
import struct
import numpy as np

MAGIC = b"VINER1"
V = 32
seed = 7
rng = np.random.default_rng(seed)
W = rng.normal(0.0, 1.0, (V, V, V)).astype("float32")
D = rng.uniform(-1.0, 1.0, (V, V, V)).astype("float32")
B = rng.normal(0.0, 0.1, (V,)).astype("float32")
emb = rng.normal(0.0, 0.3, (V, 8)).astype("float32")
rev = b"token-7f2"
names = ["W", "D", "B", "emb"]
table = {"W": W, "D": D, "B": B, "emb": emb}
out = bytearray()
out += MAGIC + b"\x00\x00"
out += struct.pack("<I", V)               # vocab_size
out += struct.pack("<I", len(names))      # n_tensors
out += struct.pack("<I", 8)               # max_gen
out += struct.pack("<I", 8)               # d_emb
out += struct.pack("<I", len(rev)) + rev  # revision
for name in names:
    a = table[name]
    out += struct.pack("<I", len(name)) + name.encode()
    out += struct.pack("<B", 0)           # dtype float32
    out += struct.pack("<B", a.ndim)
    for s in a.shape:
        out += struct.pack("<I", s)
    out += a.tobytes()
with open("/app/data/checkpoint.ckpt", "wb") as fh:
    fh.write(bytes(out))

with open("/app/data/vocab.txt", "w") as fh:
    for i in range(V):
        fh.write("%d\tvg_%03d\n" % (i, i))
print("fixtures written")
PY

# The generated fixtures land in /app/data.  No solver code is shipped; the
# image intentionally has only the shipped data so the agent authors /app tools.
RUN ls -l /app/data/checkpoint.ckpt /app/data/vocab.txt