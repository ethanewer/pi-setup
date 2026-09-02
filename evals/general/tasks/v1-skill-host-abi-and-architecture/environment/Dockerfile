FROM bench-base:ubuntu-24.04

WORKDIR /app

# C toolchain to compile the host-ABI probe.
RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

COPY files/host /app/host