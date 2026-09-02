FROM bench-base:python-3.12

WORKDIR /app

# C toolchain for the shared-memory (pthread/UPC-style) assembly deliverable.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Numerics for the pipeline-parallel deliverable.
RUN pip install --no-cache-dir numpy

COPY files/ /app/
