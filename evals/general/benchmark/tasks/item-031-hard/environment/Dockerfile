FROM bench-base:ubuntu-24.04

# C toolchain for the inference program
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Synthetic MNIST-style model: PyTorch-style state dict (ground truth) plus an
# undocumented quantized binary export to reverse-engineer, and 60 images.
COPY files/build_env.py /app/build_env.py
COPY files/reference.py /app/reference.py
COPY files/notes.txt /app/notes.txt
RUN python3 /app/build_env.py && rm /app/build_env.py