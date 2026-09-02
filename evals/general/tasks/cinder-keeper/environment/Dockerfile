FROM bench-base:ubuntu-24.04

WORKDIR /app

# Toolchain: gcc (gate), python3 (payload crafter).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc build-essential python3 \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

WORKDIR /app
