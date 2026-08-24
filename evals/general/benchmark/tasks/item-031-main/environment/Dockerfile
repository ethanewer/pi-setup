FROM bench-base:ubuntu-24.04

# C toolchain for the inference program
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Synthetic MNIST-style model + 60 raw test images; reference implementation.
COPY files/build_env.py /app/build_env.py
COPY files/reference.py /app/reference.py
RUN python3 /app/build_env.py && rm /app/build_env.py