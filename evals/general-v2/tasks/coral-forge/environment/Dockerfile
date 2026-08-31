FROM bench-base:ubuntu-24.04

WORKDIR /app

# Native toolchain for the wind-tunnel solver (serial + OpenMP builds).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc libomp-dev make python3 \
 && rm -rf /var/lib/apt/lists/*

# Shipped workbench fixture (same params.ini schema as every hidden case).
COPY files/ /app/
