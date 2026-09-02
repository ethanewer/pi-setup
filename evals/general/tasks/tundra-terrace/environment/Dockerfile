FROM bench-base:python-3.12

# Minimal dependencies: the engine reconstruction must be dependency-free
# (numpy only, no torch/triton). Corporate CA is baked into the base image.
RUN pip install --no-cache-dir numpy

WORKDIR /app
COPY files/ /app/