FROM bench-base:ubuntu-24.04

WORKDIR /app

# C toolchain for the arena allocator exercise.
RUN apt-get update && apt-get install -y gcc libc6-dev build-essential && rm -rf /var/lib/apt/lists/*

COPY files/project /app/project