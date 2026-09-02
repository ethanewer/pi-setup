FROM bench-base:ubuntu-24.04

WORKDIR /app

# Native toolchain with OpenMP runtime for the drift simulator.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc libomp-dev python3 binutils file \
 && rm -rf /var/lib/apt/lists/*

# Shipped visible fixture (hidden fixtures follow the same schema).
COPY files/ /app/
