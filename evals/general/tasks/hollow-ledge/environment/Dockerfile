FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    python3 \
    openssl \
    unzip \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# Pre-build the validation binary the agent must reverse (source kept in /app/src).
RUN gcc -O2 -o /usr/local/bin/ledgecheck /app/src/check.c