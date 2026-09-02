FROM bench-base:python-3.12

WORKDIR /app

# Numerics for the MIL forward pass: numpy for the fixture bags, CPU-only torch
# for the model (no GPU in this image).
RUN pip install --no-cache-dir -q numpy && \
    pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only visible fixture: the station config and its sensor bag.
COPY files/ /app/

# /app/input/bag.npz layout expected by the CLI contract.
RUN mkdir -p /app/input && mv /app/bag.npz /app/input/bag.npz
