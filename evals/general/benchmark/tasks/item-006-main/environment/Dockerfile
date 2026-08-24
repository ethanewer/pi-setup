FROM bench-base:ubuntu-24.04

WORKDIR /app

# C++ compiler + make for the legacy renderer.
RUN apt-get update && apt-get install -y g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

COPY files/pov2 /app/pov2