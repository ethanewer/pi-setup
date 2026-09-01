FROM bench-base:ubuntu-24.04

WORKDIR /app

# Toolchain: gcc (vault), python3 + flask (service).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc build-essential python3 python3-flask python3-pip \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

WORKDIR /app