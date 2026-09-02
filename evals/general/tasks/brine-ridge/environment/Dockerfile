# Task Dockerfile for brine-ridge.
#
# Base: python-3.12. The saltern trainer source tree and the visible dataset
# are shipped in the image; the CUDA/GPU path is intentionally enabled by
# default (USE_GPU=ON) and cannot configure on this CPU-only host, so the
# framework must be built with the GPU path disabled. No CUDA toolkit, no
# GPU device, and no network are present at run/verify time.
FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential cmake binutils file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fixtures shipped in the image (do not modify):
#   /app/saltern/       - the saltern trainer source tree (CMake, core/cpu/gpu)
#   /app/data/train.csv - visible training dataset "x1,x2,y" rows
COPY files/ /app/

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
