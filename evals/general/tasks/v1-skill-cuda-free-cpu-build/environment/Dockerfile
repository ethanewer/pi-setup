FROM bench-base:ubuntu-24.04

WORKDIR /app

# C++ toolchain for building the small project.
RUN apt-get update && apt-get install -y gcc libc6-dev g++ libc6-dev build-essential && rm -rf /var/lib/apt/lists/*

# A small project whose build is switchable between CUDA and CPU targets.
COPY files/project /app/project